#!/usr/bin/env python3
"""Run the full AgentDojo evaluation and produce the paper outputs.

    python eval/run.py --models eval/configs/*.json

Prints the plan, runs every remaining benchmark in parallel, then processes
results into the raw dump and the LaTeX tables. Resumable. Each benchmark
runs as its own worker process, python run.py worker '<spec json>'.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import signal
import sqlite3
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import camel_eval  # noqa: E402
from benchmark import (  # noqa: E402
    ATTACKS, BENCHMARK_VERSION, Benchmark, Model, REPO_ROOT, SUITES,
    TASK_TIMEOUT_S, expand, is_finalized, print_plan, split_cached,
)


def kill_group(proc: subprocess.Popen) -> None:
    try:
        os.killpg(proc.pid, signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        proc.kill()


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


def _pipeline(spec: dict, private: Path):
    if "camel_model" in spec:
        from camel_eval.worker import make_pipeline

        return make_pipeline(spec)
    from bridge import HaskellAgentPipeline

    private.mkdir(parents=True, exist_ok=True)
    config = private / "config.json"
    config.write_text(json.dumps(spec["agent_config"]))
    return HaskellAgentPipeline(spec["exe"], spec["pipeline_name"], str(config),
                                str(private / "transcript.jsonl"), private / "llm")


def run_benchmark(spec: dict) -> None:
    """Run one benchmark in this process and write its result."""
    from agentdojo.attacks.attack_registry import load_attack
    from agentdojo.benchmark import (
        TaskResults, run_task_with_injection_tasks, run_task_without_injection_tasks)
    from agentdojo.functions_runtime import FunctionCall  # noqa: F401
    from agentdojo.logging import OutputLogger
    from agentdojo.models import MODEL_NAMES
    from agentdojo.task_suite.load_suites import get_suite

    TaskResults.model_rebuild()
    logdir = Path(spec["logdir"])
    # important_instructions embeds a model name matched against MODEL_NAMES
    MODEL_NAMES.setdefault(spec["pipeline_name"], spec["attack_model_name"])
    MODEL_NAMES.setdefault(spec["pipeline_name"].removesuffix("+secpol"),
                           spec["attack_model_name"])

    suite = get_suite(spec["benchmark_version"], spec["suite"])
    slug = "-".join([spec["suite"], spec["task_id"], spec["attack"], spec["injection_task_id"]])
    private = logdir / spec["pipeline_name"] / ".agent" / slug
    pipeline = _pipeline(spec, private)
    assert pipeline.name == spec["pipeline_name"], pipeline.name

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

    if "exe" in spec:
        result_path = (logdir / spec["pipeline_name"] / spec["suite"] / spec["task_id"]
                       / spec["attack"] / f"{spec['injection_task_id']}.json")
        result = json.loads(result_path.read_text())
        result["tokens"] = _llm_token_usage(private / "llm")
        result["agent_transcript"] = str(private / "transcript.jsonl")
        result_path.write_text(json.dumps(result))
    print(f"[done] {slug}", flush=True)


def typeguard_exe(build: bool = True) -> str:
    if build:
        subprocess.run(["cabal", "build", "--write-ghc-environment-files=always", "agentdojo"],
                       cwd=REPO_ROOT, check=True)
    return subprocess.check_output(["cabal", "list-bin", "agentdojo"], cwd=REPO_ROOT,
                                   text=True).strip().splitlines()[-1]


def _spec(bench, model, logdir, benchmark_version, exe) -> dict:
    spec = {
        "suite": bench.suite, "task_id": bench.task_id, "attack": bench.attack,
        "injection_task_id": bench.injection_task_id, "variant": bench.variant,
        "benchmark_version": benchmark_version, "logdir": str(logdir / f"rep{bench.rep}"),
        "pipeline_name": model.pipeline_name(bench.system, bench.variant),
    }
    spec |= {"attack_model_name": model.attack_model_name}
    if bench.system == "typeguard":
        cmd = [exe, "--suite", bench.suite] + (["--secure"] if bench.variant == "policy" else [])
        spec |= {"exe": cmd, "agent_config": model.agent_config}
    else:
        spec |= {"camel_model": model.camel_model,
                 "reasoning_effort": model.agent_config.get("reasoningEffort")}
    return spec


def _worker_cmd(bench: Benchmark, spec: dict) -> list[str]:
    if bench.system == "typeguard":
        return [sys.executable, __file__, "worker", json.dumps(spec)]
    return camel_eval.worker_cmd(spec)


def run_benchmarks(benchmarks, models, logdir, benchmark_version, timeout_s, max_workers,
                   build: bool = True) -> dict:
    if any(b.system == "camel" for b in benchmarks):
        camel_eval.ensure_checkout()
    exe = typeguard_exe(build) if any(b.system == "typeguard" for b in benchmarks) else None

    done = {"completed": 0, "timeout": 0, "crashed": []}
    lock = threading.Lock()
    start = time.time()

    def run_one(bench: Benchmark) -> None:
        spec = _spec(bench, models[bench.model], logdir, benchmark_version, exe)
        result_path = bench.result_path(logdir, models)
        slug = f"{spec['pipeline_name']}-{bench.rep}-{bench.suite}-{bench.task_id}-{bench.attack}-{bench.injection_task_id}"
        log = logdir / ".workers" / f"{slug}.log"
        log.parent.mkdir(parents=True, exist_ok=True)

        status = "crashed"
        with log.open("ab") as lf:
            proc = subprocess.Popen(_worker_cmd(bench, spec), stdout=lf,
                                    stderr=subprocess.STDOUT, cwd=REPO_ROOT,
                                    start_new_session=True)
            try:
                proc.wait(timeout=timeout_s)
                if is_finalized(result_path):
                    status = "completed"
            except subprocess.TimeoutExpired:
                kill_group(proc)
                proc.wait(timeout=10)
                result_path.parent.mkdir(parents=True, exist_ok=True)
                result_path.write_text(json.dumps({
                    "suite_name": bench.suite, "pipeline_name": spec["pipeline_name"],
                    "user_task_id": bench.task_id, "utility": False, "security": True,
                    "error": f"killed after {timeout_s}s budget",
                    "duration": float(timeout_s)}))
                status = "timeout"
        with lock:
            if status == "crashed":
                done["crashed"].append((bench, str(log)))
            else:
                done[status] += 1
            n = done["completed"] + done["timeout"] + len(done["crashed"])
            shout = status if status == "completed" else status.upper()
            print(f"[{n}/{len(benchmarks)} {(time.time() - start) / 60:.1f}min] {shout}: {slug}",
                  flush=True)

    # camel+secpol replays the +camel recordings, so those run first
    waves = [[b for b in benchmarks if not (b.system == "camel" and b.variant == "policy")],
             [b for b in benchmarks if b.system == "camel" and b.variant == "policy"]]
    for wave in waves:
        with ThreadPoolExecutor(max_workers=max_workers) as pool:
            for f in as_completed([pool.submit(run_one, b) for b in wave]):
                f.result()
    return done


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--models", nargs="+", required=True,
                    help="model config JSONs (eval/configs/*.json)")
    ap.add_argument("--logdir", default="logs/eval")
    ap.add_argument("--suites", default=",".join(SUITES), help="comma list")
    ap.add_argument("--attacks", default=",".join(ATTACKS),
                    help="comma list. empty runs only the benign baseline")
    ap.add_argument("--systems", default="typeguard,camel")
    ap.add_argument("--repeats", type=int, default=1, help="repetitions per task")
    ap.add_argument("--max-workers", type=int, default=None,
                    help="parallel workers. default ceil(n/4)")
    ap.add_argument("--timeout", type=int, default=TASK_TIMEOUT_S,
                    help="per task budget in seconds")
    ap.add_argument("--benchmark-version", default=BENCHMARK_VERSION)
    ap.add_argument("--plan-only", action="store_true")
    ap.add_argument("--process-only", action="store_true")
    ap.add_argument("--yes", "-y", action="store_true")
    ap.add_argument("--no-build", action="store_true",
                    help="skip cabal build before locating binaries")
    args = ap.parse_args()

    models = {m.name: m for m in map(Model.load, args.models)}
    suites = [s for s in args.suites.split(",") if s]
    attacks = [a for a in args.attacks.split(",") if a]
    systems = [s for s in args.systems.split(",") if s]
    logdir = Path(args.logdir).resolve()

    if not args.process_only:
        benchmarks = expand(list(models.values()), suites, attacks, args.repeats, systems)
        to_run, cached = split_cached(benchmarks, logdir, models)
        max_workers = args.max_workers or min(max(math.ceil(len(to_run) / 4), 1), 512)
        print_plan(to_run, cached, models, logdir, max_workers)
        if args.plan_only:
            return 0
        if to_run:
            if not args.yes:
                if not sys.stdin.isatty():
                    print("stdin is not a TTY; pass --yes to run non-interactively")
                    return 1
                if input("Proceed? [y/N] ").strip().lower() not in ("y", "yes"):
                    return 1
            report = run_benchmarks(to_run, models, logdir, args.benchmark_version,
                                    args.timeout, max_workers, build=not args.no_build)
            print(f"\nRun finished: {report['completed']} completed, "
                  f"{report['timeout']} timed out, {len(report['crashed'])} crashed.")
            for bench, log in report["crashed"]:
                print(f"  CRASHED (no result): {bench}\n    worker log: {log}")
                for line in Path(log).read_text().splitlines()[-8:]:
                    print(f"    | {line}")

    from process import process

    process(logdir, models, suites, attacks, args.repeats)
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "worker":
        run_benchmark(json.loads(sys.argv[2]))
    else:
        sys.exit(main())
