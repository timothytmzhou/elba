"""Run one AgentDojo task through the Haskell agent binary.

Invoked as a worker by the runner as python bridge.py '<atom spec json>'.
The bridge speaks newline json with the binary.

    Python to Haskell.  {"prompt": ...} then {"ok": ...} or {"err": ...}
    Haskell to Python.  {"call": ..., "args": {...}} then {"done"/"failed": ...}

Each atom gets a private LLM_USER_PATH so the llm CLI conversations and token
counts stay isolated across parallel workers.
"""

from __future__ import annotations

import datetime
import enum
import json
import os
import shutil
import signal
import sqlite3
import subprocess
import sys
import threading
from pathlib import Path


def to_jsonable(obj):
    if hasattr(obj, "model_dump"):
        return obj.model_dump(mode="json")
    if isinstance(obj, (datetime.datetime, datetime.date, datetime.time)):
        return obj.isoformat()
    if isinstance(obj, enum.Enum):
        return to_jsonable(obj.value)
    if isinstance(obj, (list, tuple)):
        return [to_jsonable(x) for x in obj]
    if isinstance(obj, dict):
        return {k: to_jsonable(v) for k, v in obj.items()}
    return obj


def kill_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        proc.kill()


class HaskellAgentPipeline:
    """AgentDojo pipeline element that runs one agent binary per query."""

    def __init__(self, exe, name, config_path, log_path, llm_user_dir, timeout_s):
        self.exe, self.name = exe, name
        self.config_path, self.log_path = config_path, log_path
        self.llm_user_dir, self.timeout_s = llm_user_dir, timeout_s

    def _child_env(self) -> dict:
        self.llm_user_dir.mkdir(parents=True, exist_ok=True)
        default = Path(os.environ.get("LLM_USER_PATH",
                                      Path.home() / ".config" / "io.datasette.llm"))
        if (default / "keys.json").exists() and not (self.llm_user_dir / "keys.json").exists():
            shutil.copy(default / "keys.json", self.llm_user_dir / "keys.json")
        return dict(os.environ) | {"LLM_USER_PATH": str(self.llm_user_dir)}

    def _send(self, proc, obj) -> None:
        proc.stdin.write(json.dumps(obj, default=to_jsonable) + "\n")
        proc.stdin.flush()

    def query(self, query, runtime, env=None, messages=(), extra_args={}):
        from agentdojo.functions_runtime import EmptyEnv, FunctionCall
        from agentdojo.logging import Logger
        from agentdojo.types import ChatAssistantMessage, ChatUserMessage, TextContentBlock

        env = env if env is not None else EmptyEnv()
        proc = subprocess.Popen(
            [self.exe, "--config", self.config_path, "--log-path", self.log_path],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1,
            env=self._child_env(), start_new_session=True)
        timed_out = threading.Event()

        def watchdog():
            if proc.poll() is None:
                timed_out.set()
                kill_group(proc)

        timer = threading.Timer(self.timeout_s, watchdog)
        timer.start()
        tool_calls = []
        try:
            self._send(proc, {"prompt": query})
            while True:
                line = proc.stdout.readline()
                if not line:
                    raise RuntimeError(f"agent closed stdout early (exit {proc.poll()})")
                msg = json.loads(line)
                if "call" in msg:
                    args = msg.get("args") or {}
                    tool_calls.append(FunctionCall(function=msg["call"], args=args))
                    result, error = runtime.run_function(env, msg["call"], args)
                    self._send(proc, {"err": error} if error else {"ok": to_jsonable(result)})
                elif "done" in msg or "failed" in msg:
                    answer = msg.get("done") or msg.get("failed")
                    break
        except Exception:
            kill_group(proc)
            if not timed_out.is_set():
                raise
            answer = f"task exceeded {self.timeout_s}s timeout"
        finally:
            timer.cancel()
            proc.stdin.close()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                kill_group(proc)

        new_messages = list(messages) + [
            ChatUserMessage(role="user", content=[TextContentBlock(type="text", content=query)]),
            ChatAssistantMessage(role="assistant", tool_calls=tool_calls,
                                 content=[TextContentBlock(type="text", content=answer)])]
        # Log so the saved result carries the agent output.
        Logger.get().log(new_messages)
        return answer, runtime, env, new_messages, extra_args


def _llm_token_usage(llm_user_dir: Path) -> dict | None:
    db = llm_user_dir / "logs.db"
    if not db.exists():
        return None
    try:
        with sqlite3.connect(db) as conn:
            row = conn.execute("SELECT COALESCE(SUM(input_tokens),0), "
                               "COALESCE(SUM(output_tokens),0), COUNT(*) FROM responses").fetchone()
        return {"input": row[0], "output": row[1], "llm_calls": row[2]}
    except sqlite3.Error:
        return None


def run_task(spec: dict) -> None:
    """Run one typeguard atom in this process and write its result."""
    from agentdojo.attacks.attack_registry import load_attack
    from agentdojo.benchmark import (
        TaskResults, run_task_with_injection_tasks, run_task_without_injection_tasks)
    from agentdojo.functions_runtime import FunctionCall  # noqa: F401
    from agentdojo.logging import OutputLogger
    from agentdojo.models import MODEL_NAMES
    from agentdojo.task_suite.load_suites import get_suite

    TaskResults.model_rebuild()
    logdir = Path(spec["logdir"])
    # important_instructions embeds a model name matched against MODEL_NAMES.
    MODEL_NAMES.setdefault(spec["pipeline_name"], spec["attack_model_name"])

    suite = get_suite(spec["benchmark_version"], spec["suite"])
    slug = "-".join([spec["suite"], spec["task_id"], spec["attack"], spec["injection_task_id"]])
    private = logdir / spec["pipeline_name"] / ".agent" / slug
    private.mkdir(parents=True, exist_ok=True)
    pipeline = HaskellAgentPipeline(
        spec["exe"], spec["pipeline_name"], spec["config_path"],
        str(private / "transcript.jsonl"), private / "llm", spec["timeout_s"])

    with OutputLogger(str(logdir)):
        task = suite.get_user_task_by_id(spec["task_id"])
        if spec["attack"] == "none":
            run_task_without_injection_tasks(suite, pipeline, task, logdir, force_rerun=False,
                                             benchmark_version=spec["benchmark_version"])
        else:
            attack = load_attack(spec["attack"], suite, pipeline)
            run_task_with_injection_tasks(suite, pipeline, task, attack, logdir, force_rerun=False,
                                          injection_tasks=[spec["injection_task_id"]],
                                          benchmark_version=spec["benchmark_version"])

    result_path = (logdir / spec["pipeline_name"] / spec["suite"] / spec["task_id"]
                   / spec["attack"] / f"{spec['injection_task_id']}.json")
    result = json.loads(result_path.read_text())
    result["tokens"] = _llm_token_usage(private / "llm")
    result["agent_transcript"] = str(private / "transcript.jsonl")
    result_path.write_text(json.dumps(result))
    print(f"[done] {slug}: utility={result['utility']} security={result['security']}", flush=True)


if __name__ == "__main__":
    run_task(json.loads(sys.argv[1]))
