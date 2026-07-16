"""Experiment execution: run atoms in parallel, one OS process each.

Three roles live here, all "run side" (data processing is in process.py):

1. `HaskellAgentPipeline` — the AgentDojo pipeline element that drives the
   Haskell agent binary over a line-JSON bridge (stdin/stdout of the child):

       Python -> Haskell:  {"prompt": ...} then {"ok": ...} | {"err": ...}
       Haskell -> Python:  {"call": ..., "args": {...}}* then
                           {"done": ...} | {"failed": ...}

2. The worker entry point (`python execute.py '<atom json>'`) — runs ONE
   typeguard atom inside its own process and writes the standard AgentDojo
   result JSON, augmented with measured token usage. CaMeL atoms use the
   analogous camel-eval/camel_worker.py inside CaMeL's own environment.

3. `run_atoms` — the parallel supervisor: bounded pool, per-atom hard
   timeout (kills the worker's process group and records the conventional
   utility=False / security=True failure result, as the previous
   orchestrator and AgentDojo's own error handling do), and one retry for
   workers that die without writing a result.

Parallel-safety of the agent: the Haskell binary shells out to the `llm`
CLI, whose `-c` flag continues "the most recent conversation" in a shared
sqlite database — concurrent agents would cross-contaminate. Each atom
therefore gets a private LLM_USER_PATH; the provider key is copied in from
the default llm dir (or supplied via OPENAI_API_KEY). The private dir also
gives us exact per-task token counts, which the worker records into the
result JSON and the plan uses to refine cost estimates.
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

from experiment import Atom, Model, is_finalized, EVAL_DIR, REPO_ROOT

# ---------------------------------------------------------------------------
# Bridge


def to_jsonable(obj):
    """AgentDojo tool results -> JSON. Pydantic models are dumped in JSON
    mode so datetimes/enums (workspace/travel/banking suites) serialize."""
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
    """One agent conversation per query() call, by spawning the binary."""

    def __init__(self, exe: str, name: str, config_path: str, log_path: str,
                 llm_user_dir: Path, timeout_s: int):
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

    def _send(self, proc: subprocess.Popen, obj: dict) -> None:
        proc.stdin.write(json.dumps(obj, default=to_jsonable) + "\n")
        proc.stdin.flush()

    def query(self, query, runtime, env=None, messages=(), extra_args={}):
        from agentdojo.functions_runtime import EmptyEnv, FunctionCall
        from agentdojo.types import ChatAssistantMessage, ChatUserMessage, TextContentBlock

        env = env if env is not None else EmptyEnv()
        cmd = [self.exe, "--config", self.config_path, "--log-path", self.log_path]
        proc = subprocess.Popen(
            cmd, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
            bufsize=1, env=self._child_env(), start_new_session=True,
        )
        timed_out = threading.Event()

        def watchdog():
            if proc.poll() is None:
                timed_out.set()
                _kill_group(proc)

        timer = threading.Timer(self.timeout_s, watchdog)
        timer.start()
        tool_calls: list = []
        try:
            self._send(proc, {"prompt": query})
            while True:
                line = proc.stdout.readline()
                if not line:
                    raise RuntimeError(
                        f"agent binary closed stdout before done/failed (exit {proc.poll()})")
                msg = json.loads(line)
                if "call" in msg:
                    args = msg.get("args") or {}
                    tool_calls.append(FunctionCall(function=msg["call"], args=args))
                    result, error = runtime.run_function(env, msg["call"], args)
                    self._send(proc, {"ok": to_jsonable(result)} if error is None
                               else {"err": error})
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
            ChatUserMessage(role="user",
                            content=[TextContentBlock(type="text", content=query)]),
            ChatAssistantMessage(role="assistant",
                                 content=[TextContentBlock(type="text", content=answer)],
                                 tool_calls=tool_calls),
        ]
        # Record the conversation with the active TraceLogger so the saved
        # result JSON (and hence dump.jsonl) carries the agent's output.
        from agentdojo.logging import Logger

        Logger.get().log(new_messages)
        return answer, runtime, env, new_messages, extra_args


# ---------------------------------------------------------------------------
# Worker: run one typeguard atom (invoked as `python execute.py '<json>'`)


def _llm_token_usage(llm_user_dir: Path) -> dict | None:
    """Sum token counts the `llm` CLI logged for this atom's conversations."""
    db = llm_user_dir / "logs.db"
    if not db.exists():
        return None
    try:
        with sqlite3.connect(db) as conn:
            row = conn.execute(
                "SELECT COALESCE(SUM(input_tokens),0), COALESCE(SUM(output_tokens),0), COUNT(*)"
                " FROM responses").fetchone()
        return {"input": row[0], "output": row[1], "llm_calls": row[2]}
    except sqlite3.Error:
        return None


def worker_main(spec: dict) -> None:
    from agentdojo.attacks.attack_registry import load_attack
    from agentdojo.benchmark import (
        TaskResults, run_task_with_injection_tasks, run_task_without_injection_tasks)
    from agentdojo.functions_runtime import FunctionCall  # noqa: F401 (model_rebuild)
    from agentdojo.logging import OutputLogger
    from agentdojo.models import MODEL_NAMES
    from agentdojo.task_suite.load_suites import get_suite

    TaskResults.model_rebuild()

    logdir = Path(spec["logdir"])
    # `important_instructions` embeds a model name looked up by substring-
    # matching pipeline.name against MODEL_NAMES; register ours.
    MODEL_NAMES.setdefault(spec["pipeline_name"], spec["attack_model_name"])

    suite = get_suite(spec["benchmark_version"], spec["suite"])
    slug = "-".join([spec["suite"], spec["task_id"], spec["attack"], spec["injection_task_id"]])
    private = logdir / spec["pipeline_name"] / ".agent" / slug
    pipeline = HaskellAgentPipeline(
        exe=spec["exe"], name=spec["pipeline_name"], config_path=spec["config_path"],
        log_path=str(private / "transcript.jsonl"), llm_user_dir=private / "llm",
        timeout_s=spec["timeout_s"],
    )
    private.mkdir(parents=True, exist_ok=True)

    with OutputLogger(str(logdir)):
        if spec["attack"] == "none":
            task = suite.get_user_task_by_id(spec["task_id"])
            run_task_without_injection_tasks(
                suite, pipeline, task, logdir, force_rerun=False,
                benchmark_version=spec["benchmark_version"])
        else:
            attack = load_attack(spec["attack"], suite, pipeline)
            task = suite.get_user_task_by_id(spec["task_id"])
            run_task_with_injection_tasks(
                suite, pipeline, task, attack, logdir, force_rerun=False,
                injection_tasks=[spec["injection_task_id"]],
                benchmark_version=spec["benchmark_version"])

    # Augment the result JSON with measured token usage + transcript path.
    result_path = (logdir / spec["pipeline_name"] / spec["suite"] / spec["task_id"]
                   / spec["attack"] / f"{spec['injection_task_id']}.json")
    result = json.loads(result_path.read_text())
    result["tokens"] = _llm_token_usage(private / "llm")
    result["agent_transcript"] = str(private / "transcript.jsonl")
    result_path.write_text(json.dumps(result))
    print(f"[done] {slug}: utility={result['utility']} security={result['security']}",
          flush=True)


# ---------------------------------------------------------------------------
# CaMeL checkout + worker command

CAMEL_REPO = "https://github.com/google-research/camel-prompt-injection.git"
CAMEL_PATCHED = ["main.py", "src/camel/models.py",
                 "src/camel/pipeline_elements/privileged_llm.py"]


def ensure_camel_checkout() -> Path:
    camel = REPO_ROOT / "camel"
    if not camel.exists():
        print(f"[camel] cloning into {camel}", flush=True)
        subprocess.run(["git", "clone", CAMEL_REPO, str(camel)], check=True)
    clean = subprocess.run(["git", "diff", "--quiet", "--", *CAMEL_PATCHED],
                           cwd=camel).returncode == 0
    if clean:
        print("[camel] applying our-changes.patch", flush=True)
        subprocess.run(["git", "apply", "--3way",
                        str(EVAL_DIR / "camel-eval" / "our-changes.patch")],
                       cwd=camel, check=True)
    env_file = camel / ".env"
    if not env_file.exists():
        env_file.write_text("")
    if "OPENAI_API_KEY" not in env_file.read_text() and os.environ.get("OPENAI_API_KEY"):
        with env_file.open("a") as f:
            f.write(f'\nOPENAI_API_KEY="{os.environ["OPENAI_API_KEY"]}"\n')
    return camel


def resolve_typeguard_exes(atoms: list[Atom], build: bool = True) -> dict[str, str]:
    """cabal-build and locate every agentdojo-<suite>[-secure] binary needed."""
    targets = sorted({
        f"agentdojo-{a.suite}" + ("-secure" if a.variant == "policy" else "")
        for a in atoms if a.system == "typeguard"
    })
    if not targets:
        return {}
    if build:
        subprocess.run(["cabal", "build", "--write-ghc-environment-files=always",
                        *targets], cwd=REPO_ROOT, check=True)
    return {
        t: subprocess.check_output(["cabal", "list-bin", t], cwd=REPO_ROOT,
                                   text=True).strip().splitlines()[-1]
        for t in targets
    }


# ---------------------------------------------------------------------------
# Parallel supervisor


def _atom_spec(atom: Atom, model: Model, logdir: Path, benchmark_version: str,
               timeout_s: int, exes: dict[str, str], config_paths: dict[str, Path]) -> dict:
    spec = {
        "suite": atom.suite, "task_id": atom.task_id, "attack": atom.attack,
        "injection_task_id": atom.injection_task_id,
        "variant": atom.variant,
        "benchmark_version": benchmark_version,
        "logdir": str(logdir / f"rep{atom.rep}"),
        "pipeline_name": model.pipeline_name(atom.system, atom.variant),
        "timeout_s": timeout_s,
    }
    if atom.system == "typeguard":
        target = f"agentdojo-{atom.suite}" + ("-secure" if atom.variant == "policy" else "")
        spec |= {"exe": exes[target], "config_path": str(config_paths[atom.model]),
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
    """Conventional failure record (utility=False, security=True), matching
    AgentDojo's own error handling and the previous orchestrator."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "suite_name": atom.suite, "pipeline_name": spec["pipeline_name"],
        "user_task_id": atom.task_id,
        "injection_task_id": None if atom.attack == "none" else atom.injection_task_id,
        "attack_type": None if atom.attack == "none" else atom.attack,
        "injections": {}, "benchmark_version": spec["benchmark_version"],
        "evaluation_timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "utility": False, "security": True, "error": reason,
        "duration": float(spec["timeout_s"]),
        "messages": [  # TaskResults requires >= 2 messages
            {"role": "system", "content": [{"type": "text", "content": ""}]},
            {"role": "user", "content": [{"type": "text", "content": ""}]},
        ],
    }))


def run_atoms(atoms: list[Atom], models: dict[str, Model], logdir: Path,
              benchmark_version: str, timeout_s: int, max_workers: int,
              build: bool = True) -> dict:
    if any(a.system == "camel" for a in atoms):
        ensure_camel_checkout()
    exes = resolve_typeguard_exes(atoms, build=build)

    config_paths = {}
    for model in models.values():
        p = logdir / ".configs" / f"{model.name}.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(model.agent_config, indent=2))
        config_paths[model.name] = p

    done = {"completed": 0, "timeout": 0, "crashed": []}
    lock = threading.Lock()
    start = time.time()

    def run_one(atom: Atom) -> None:
        model = models[atom.model]
        spec = _atom_spec(atom, model, logdir, benchmark_version, timeout_s,
                          exes, config_paths)
        result_path = atom.result_path(logdir, models)
        log = logdir / ".workers" / f"{spec['pipeline_name']}-{atom.rep}-{atom.suite}-{atom.task_id}-{atom.attack}-{atom.injection_task_id}.log"
        log.parent.mkdir(parents=True, exist_ok=True)

        status = "crashed"
        for _attempt in range(2):  # one retry for infra crashes
            with log.open("ab") as lf:
                proc = subprocess.Popen(_worker_cmd(atom, spec), stdout=lf,
                                        stderr=subprocess.STDOUT, cwd=REPO_ROOT,
                                        start_new_session=True)
                try:
                    # slack over the in-worker watchdog, which fires first
                    proc.wait(timeout=timeout_s + 120)
                except subprocess.TimeoutExpired:
                    _kill_group(proc)
                    proc.wait(timeout=10)
                    _write_timeout_result(result_path, atom, spec,
                                          f"killed after {timeout_s}s per-task budget")
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
            print(f"[{n}/{len(atoms)} {(time.time() - start) / 60:.1f}min] {status}: "
                  f"{atom.system}/{atom.variant}/{atom.model}/rep{atom.rep}/{atom.suite}/"
                  f"{atom.task_id}/{atom.attack}/{atom.injection_task_id}", flush=True)

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        futures = [pool.submit(run_one, a) for a in atoms]
        for f in as_completed(futures):
            f.result()
    return done


if __name__ == "__main__":
    worker_main(json.loads(sys.argv[1]))
