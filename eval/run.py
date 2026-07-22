#!/usr/bin/env python3
"""Run the full AgentDojo evaluation and produce the paper outputs.

    python eval/run.py --models eval/configs/*.json

Each benchmark runs as its own worker process.
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
from collections import Counter
from dataclasses import asdict, replace
from pathlib import Path

from tqdm import tqdm
from tqdm.contrib.concurrent import thread_map

sys.path.insert(0, str(Path(__file__).resolve().parent))

import camel_eval  # noqa: E402
from benchmark import (  # noqa: E402
    ATTACKS, BENCHMARK_VERSION, Benchmark, REPO_ROOT, SUITES, TASK_TIMEOUT_S,
    expand, is_benign, pipeline_name, print_plan, result_path, slug, split_cached,
)
from config import Model, attack_persona, load_model, on_bedrock  # noqa: E402
from result import Outcome, RunReport  # noqa: E402


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


def run_benchmark(bench: Benchmark, model: Model, logdir: Path, benchmark_version: str,
                  bedrock: bool = False) -> None:
    if bench.system == "camel":
        from camel_eval.worker import run_camel

        run_camel(bench, model, logdir, benchmark_version, bedrock)
    else:
        run_typeguard(bench, model, logdir, benchmark_version)
    print(f"[done] {slug(bench)}", flush=True)


def run_agentdojo_task(bench: Benchmark, model: Model, logdir: Path, benchmark_version: str,
                       pipeline) -> None:
    from agentdojo.attacks.attack_registry import load_attack, register_attack
    from agentdojo.attacks.baseline_attacks import DirectAttack
    from agentdojo.benchmark import (
        TaskResults, run_task_with_injection_tasks, run_task_without_injection_tasks)
    from agentdojo.functions_runtime import FunctionCall  # noqa: F401
    from agentdojo.logging import OutputLogger
    from agentdojo.models import MODEL_NAMES
    from agentdojo.task_suite.load_suites import get_suite

    # Direct TODO injection under a name that selects the compromised subagent eval
    class AdversarialAttack(DirectAttack):
        name = "adversarial"
    register_attack(AdversarialAttack)

    TaskResults.model_rebuild()
    rep_dir = logdir / f"rep{bench.rep}"
    # important_instructions embeds a model name matched against MODEL_NAMES.
    persona = attack_persona(model)
    MODEL_NAMES.setdefault(pipeline.name, persona)
    MODEL_NAMES.setdefault(pipeline.name.removesuffix("+secpol"), persona)

    suite = get_suite(benchmark_version, bench.suite)
    with OutputLogger(str(rep_dir)):
        task = suite.get_user_task_by_id(bench.task_id)
        if is_benign(bench):
            run_task_without_injection_tasks(suite, pipeline, task, rep_dir, force_rerun=False,
                                             benchmark_version=benchmark_version)
        else:
            attack = load_attack(bench.attack, suite, pipeline)
            run_task_with_injection_tasks(suite, pipeline, task, attack, rep_dir, force_rerun=False,
                                          injection_tasks=[bench.injection_task_id],
                                          benchmark_version=benchmark_version)


def run_typeguard(bench: Benchmark, model: Model, logdir: Path, benchmark_version: str) -> None:
    from bridge import HaskellAgentPipeline

    private = logdir / f"rep{bench.rep}" / pipeline_name(bench) / ".agent" / slug(bench)
    private.mkdir(parents=True, exist_ok=True)
    config = private / "config.json"
    agent_config = model.agent_config
    if bench.attack == "adversarial":
        agent_config = replace(agent_config, evalAdversarially=True)
    config.write_text(json.dumps(asdict(agent_config)))
    cmd = [typeguard_exe(), "--suite", bench.suite] + (["--secure"] if bench.variant == "policy" else [])
    pipeline = HaskellAgentPipeline(cmd, pipeline_name(bench), str(config),
                                    str(private / "transcript.jsonl"), private / "llm")
    run_agentdojo_task(bench, model, logdir, benchmark_version, pipeline)

    path = result_path(bench, logdir)
    result = json.loads(path.read_text())
    result["tokens"] = _llm_token_usage(private / "llm")
    result["agent_transcript"] = str(private / "transcript.jsonl")
    path.write_text(json.dumps(result))


def build_typeguard() -> None:
    subprocess.run(["cabal", "build", "--write-ghc-environment-files=always", "agentdojo"],
                   cwd=REPO_ROOT, check=True)


def typeguard_exe() -> str:
    return subprocess.check_output(["cabal", "list-bin", "agentdojo"], cwd=REPO_ROOT,
                                   text=True).strip().splitlines()[-1]


def _worker_cmd(bench: Benchmark, config_path: str, logdir: Path, benchmark_version: str,
                bedrock: bool) -> list[str]:
    args = ["worker", json.dumps(asdict(bench)), config_path, str(logdir), benchmark_version]
    args += ["--bedrock"] if bedrock else []
    if bench.system == "typeguard":
        return [sys.executable, __file__, *args]
    return camel_eval.worker_cmd(args)


def run_with_timeout(cmd: list[str], log: Path, timeout_s: int) -> Outcome:
    log.parent.mkdir(parents=True, exist_ok=True)
    with log.open("ab") as out:
        proc = subprocess.Popen(cmd, stdout=out, stderr=subprocess.STDOUT,
                                cwd=REPO_ROOT, start_new_session=True)
        try:
            proc.wait(timeout=timeout_s)
            return Outcome.COMPLETED
        except subprocess.TimeoutExpired:
            kill_group(proc)  # the worker spawns llm and uv children
            proc.wait(timeout=10)
            return Outcome.TIMEOUT


def _record_timeout(bench: Benchmark, logdir: Path, timeout_s: int) -> None:
    # A killed agent never converged and so never performed the injection.
    # security False means the attack was resisted, a pass.
    path = result_path(bench, logdir)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({"utility": False, "security": False,
                                "error": f"killed after {timeout_s}s budget",
                                "duration": float(timeout_s)}))


def run_benchmarks(benchmarks: list[Benchmark], configs: dict[str, str], logdir: Path,
                   benchmark_version: str, timeout_s: int, max_workers: int,
                   build: bool = True, bedrock: bool = False) -> RunReport:
    if any(b.system == "camel" for b in benchmarks):
        camel_eval.ensure_checkout()
    if build and any(b.system == "typeguard" for b in benchmarks):
        build_typeguard()

    def run_task(bench: Benchmark) -> Outcome:
        cmd = _worker_cmd(bench, configs[bench.model], logdir, benchmark_version, bedrock)
        outcome = run_with_timeout(cmd, logdir / ".workers" / f"{slug(bench)}.log", timeout_s)
        if outcome is Outcome.TIMEOUT:
            _record_timeout(bench, logdir, timeout_s)
            tqdm.write(f"TIMEOUT: {slug(bench)}")
        return outcome

    # The policy replay runs as a second wave over the recordings of the first.
    record = [b for b in benchmarks if not (b.system == "camel" and b.variant == "policy")]
    replay = [b for b in benchmarks if b.system == "camel" and b.variant == "policy"]
    tally = Counter()
    for wave in (record, replay):
        if wave:
            tally.update(thread_map(run_task, wave, max_workers=max_workers))
    return RunReport(completed=tally[Outcome.COMPLETED], timeout=tally[Outcome.TIMEOUT])


def run_worker_argv(argv: list[str]) -> None:
    bench = Benchmark(**json.loads(argv[2]))
    bedrock = "--bedrock" in argv
    model = load_model(argv[3])
    run_benchmark(bench, on_bedrock(model) if bedrock else model, Path(argv[4]), argv[5], bedrock)


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
    ap.add_argument("--no-benign", action="store_true",
                    help="skip the benign baseline, e.g. the adversarial table has no Safe column")
    ap.add_argument("--max-workers", type=int, default=None,
                    help="parallel workers. default ceil(n/4)")
    ap.add_argument("--timeout", type=int, default=TASK_TIMEOUT_S,
                    help="per task budget in seconds")
    ap.add_argument("--benchmark-version", default=BENCHMARK_VERSION)
    ap.add_argument("--bedrock", action="store_true",
                    help="run models with a bedrock_model id through Bedrock")
    ap.add_argument("--plan-only", action="store_true")
    ap.add_argument("--process-only", action="store_true")
    ap.add_argument("--no-confirm", "-y", action="store_true",
                    help="skip the run confirmation prompt")
    ap.add_argument("--no-build", action="store_true",
                    help="skip cabal build before locating binaries")
    args = ap.parse_args()

    configs, models = {}, {}
    for p in args.models:
        path = str(Path(p).resolve())
        m = load_model(path)
        configs[m.name], models[m.name] = path, m
    suites = [s for s in args.suites.split(",") if s]
    attacks = [a for a in args.attacks.split(",") if a]
    systems = [s for s in args.systems.split(",") if s]
    logdir = Path(args.logdir).resolve()

    if not args.process_only:
        benchmarks = expand(list(models.values()), suites, attacks, args.repeats, systems)
        if args.no_benign:
            benchmarks = [b for b in benchmarks if not is_benign(b)]
        to_run, cached = split_cached(benchmarks, logdir)
        max_workers = args.max_workers or min(max(math.ceil(len(to_run) / 4), 1), 512)
        print_plan(to_run, cached, max_workers)
        if args.plan_only:
            return 0
        if to_run:
            if not args.no_confirm:
                if not sys.stdin.isatty():
                    print("stdin is not a TTY; pass --no-confirm to run non-interactively")
                    return 1
                if input("Proceed? [y/N] ").strip().lower() not in ("y", "yes"):
                    return 1
            report = run_benchmarks(to_run, configs, logdir, args.benchmark_version,
                                    args.timeout, max_workers, build=not args.no_build,
                                    bedrock=args.bedrock)
            print(f"\nRun finished: {report.completed} completed, "
                  f"{report.timeout} timed out.")

    from process import process

    process(logdir, models, suites)
    return 0


if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "worker":
        run_worker_argv(sys.argv)
    else:
        sys.exit(main())
