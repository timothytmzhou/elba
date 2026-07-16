"""Run atoms in parallel, one OS process each.

The bridge speaks newline json with the Haskell agent binary.

    Python to Haskell.  {"prompt": ...} then {"ok": ...} or {"err": ...}
    Haskell to Python.  {"call": ..., "args": {...}} then {"done"/"failed": ...}

Each agent shells out to the llm CLI whose continue flag resumes the most
recent conversation in a shared database, so every atom gets a private
LLM_USER_PATH. That private dir is also where token counts are read from.
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
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

from experiment import Atom, Model, EVAL_DIR, REPO_ROOT, is_finalized


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


def _kill_group(proc: subprocess.Popen) -> None:
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
                _kill_group(proc)

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
            _kill_group(proc)
            if not timed_out.is_set():
                raise
            answer = f"task exceeded {self.timeout_s}s timeout"
        finally:
            timer.cancel()
            proc.stdin.close()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                _kill_group(proc)

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


def worker_main(spec: dict) -> None:
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
            run_task_without_injection_tasks(suite, pipeline, task, logdir,
                                             force_rerun=False,
                                             benchmark_version=spec["benchmark_version"])
        else:
            attack = load_attack(spec["attack"], suite, pipeline)
            run_task_with_injection_tasks(suite, pipeline, task, attack, logdir,
                                          force_rerun=False,
                                          injection_tasks=[spec["injection_task_id"]],
                                          benchmark_version=spec["benchmark_version"])

    result_path = (logdir / spec["pipeline_name"] / spec["suite"] / spec["task_id"]
                   / spec["attack"] / f"{spec['injection_task_id']}.json")
    result = json.loads(result_path.read_text())
    result["tokens"] = _llm_token_usage(private / "llm")
    result["agent_transcript"] = str(private / "transcript.jsonl")
    result_path.write_text(json.dumps(result))
    print(f"[done] {slug}: utility={result['utility']} security={result['security']}", flush=True)


CAMEL_REPO = "https://github.com/google-research/camel-prompt-injection.git"
CAMEL_PATCHED = ["main.py", "src/camel/models.py",
                 "src/camel/pipeline_elements/privileged_llm.py"]


def ensure_camel_checkout() -> Path:
    camel = REPO_ROOT / "camel"
    if not camel.exists():
        print(f"[camel] cloning into {camel}", flush=True)
        subprocess.run(["git", "clone", CAMEL_REPO, str(camel)], check=True)
    if subprocess.run(["git", "diff", "--quiet", "--", *CAMEL_PATCHED], cwd=camel).returncode == 0:
        print("[camel] applying our-changes.patch", flush=True)
        subprocess.run(["git", "apply", "--3way",
                        str(EVAL_DIR / "camel-eval" / "our-changes.patch")], cwd=camel, check=True)
    env_file = camel / ".env"
    if not env_file.exists():
        env_file.write_text("")
    if "OPENAI_API_KEY" not in env_file.read_text() and os.environ.get("OPENAI_API_KEY"):
        with env_file.open("a") as f:
            f.write(f'\nOPENAI_API_KEY="{os.environ["OPENAI_API_KEY"]}"\n')
    return camel


def _target(atom: Atom) -> str:
    return f"agentdojo-{atom.suite}" + ("-secure" if atom.variant == "policy" else "")


def resolve_typeguard_exes(atoms: list[Atom], build: bool = True) -> dict[str, str]:
    targets = sorted({_target(a) for a in atoms if a.system == "typeguard"})
    if not targets:
        return {}
    if build:
        subprocess.run(["cabal", "build", "--write-ghc-environment-files=always", *targets],
                       cwd=REPO_ROOT, check=True)
    return {t: subprocess.check_output(["cabal", "list-bin", t], cwd=REPO_ROOT,
                                       text=True).strip().splitlines()[-1] for t in targets}


def _atom_spec(atom, model, logdir, benchmark_version, timeout_s, exes, config_paths) -> dict:
    spec = {
        "suite": atom.suite, "task_id": atom.task_id, "attack": atom.attack,
        "injection_task_id": atom.injection_task_id, "variant": atom.variant,
        "benchmark_version": benchmark_version, "logdir": str(logdir / f"rep{atom.rep}"),
        "pipeline_name": model.pipeline_name(atom.system, atom.variant), "timeout_s": timeout_s,
    }
    if atom.system == "typeguard":
        spec |= {"exe": exes[_target(atom)], "config_path": str(config_paths[atom.model]),
                 "attack_model_name": model.attack_model_name}
    else:
        spec |= {"camel_model": model.camel_model,
                 "reasoning_effort": model.agent_config.get("reasoningEffort")}
    return spec


def _worker_cmd(atom: Atom, spec: dict) -> list[str]:
    if atom.system == "typeguard":
        return [sys.executable, str(EVAL_DIR / "execute.py"), json.dumps(spec)]
    uv = shutil.which("uv") or os.path.expanduser("~/.local/bin/uv")
    camel = REPO_ROOT / "camel"
    return [uv, "run", "--project", str(camel), "--env-file", str(camel / ".env"),
            "python", str(EVAL_DIR / "camel-eval" / "camel_worker.py"), json.dumps(spec)]


def _write_timeout_result(path: Path, atom: Atom, spec: dict, reason: str) -> None:
    # utility False and security True is AgentDojo's convention for failures.
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "suite_name": atom.suite, "pipeline_name": spec["pipeline_name"],
        "user_task_id": atom.task_id,
        "injection_task_id": None if atom.benign else atom.injection_task_id,
        "attack_type": None if atom.benign else atom.attack,
        "injections": {}, "benchmark_version": spec["benchmark_version"],
        "evaluation_timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "utility": False, "security": True, "error": reason,
        "duration": float(spec["timeout_s"]),
        "messages": [{"role": "system", "content": [{"type": "text", "content": ""}]},
                     {"role": "user", "content": [{"type": "text", "content": ""}]}],
    }))


def _write_agent_configs(models, logdir) -> dict[str, Path]:
    paths = {}
    for model in models.values():
        p = logdir / ".configs" / f"{model.name}.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(model.agent_config, indent=2))
        paths[model.name] = p
    return paths


def run_atoms(atoms, models, logdir, benchmark_version, timeout_s, max_workers,
              build: bool = True) -> dict:
    if any(a.system == "camel" for a in atoms):
        ensure_camel_checkout()
    exes = resolve_typeguard_exes(atoms, build=build)
    config_paths = _write_agent_configs(models, logdir)

    done = {"completed": 0, "timeout": 0, "crashed": []}
    lock = threading.Lock()
    start = time.time()

    def run_one(atom: Atom) -> None:
        spec = _atom_spec(atom, models[atom.model], logdir, benchmark_version,
                          timeout_s, exes, config_paths)
        result_path = atom.result_path(logdir, models)
        slug = f"{spec['pipeline_name']}-{atom.rep}-{atom.suite}-{atom.task_id}-{atom.attack}-{atom.injection_task_id}"
        log = logdir / ".workers" / f"{slug}.log"
        log.parent.mkdir(parents=True, exist_ok=True)

        status = "crashed"
        for _ in range(2):  # one retry for a worker that dies without a result
            with log.open("ab") as lf:
                proc = subprocess.Popen(_worker_cmd(atom, spec), stdout=lf,
                                        stderr=subprocess.STDOUT, cwd=REPO_ROOT,
                                        start_new_session=True)
                try:
                    proc.wait(timeout=timeout_s + 120)
                except subprocess.TimeoutExpired:
                    _kill_group(proc)
                    proc.wait(timeout=10)
                    _write_timeout_result(result_path, atom, spec,
                                          f"killed after {timeout_s}s budget")
                    status = "timeout"
                    break
            if is_finalized(result_path):
                status = "completed"
                break
        with lock:
            if status == "crashed":
                done["crashed"].append((atom, str(log)))
            else:
                done[status] += 1
            n = done["completed"] + done["timeout"] + len(done["crashed"])
            print(f"[{n}/{len(atoms)} {(time.time() - start) / 60:.1f}min] {status}: {slug}",
                  flush=True)

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        for f in as_completed([pool.submit(run_one, a) for a in atoms]):
            f.result()
    return done


if __name__ == "__main__":
    worker_main(json.loads(sys.argv[1]))
