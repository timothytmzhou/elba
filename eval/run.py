#!/usr/bin/env python3
"""Run the full AgentDojo evaluation and produce the paper outputs.

One command does everything — prints the plan (task counts + cost estimate
from OpenAI's published pricing), runs every remaining task evaluation in
parallel (TypeGuard and CaMeL, with and without policies, benign and under
attack), then processes results into the raw data dump and the LaTeX tables:

    python eval/run.py --models eval/configs/*.json

Execution is resumable: finished task evaluations are skipped, so rerunning
the same command continues where it left off. Running and processing are
separate modules (execute.py / process.py); `--plan-only` stops after the
plan, `--process-only` skips straight to processing existing results.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from experiment import (  # noqa: E402
    ATTACKS, BENCHMARK_VERSION, Model, SUITES, TASK_TIMEOUT_S,
    expand, print_plan, split_cached,
)


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--models", nargs="+", required=True,
                    help="model config JSONs (eval/configs/*.json)")
    ap.add_argument("--logdir", default="logs/eval")
    ap.add_argument("--suites", default=",".join(SUITES),
                    help=f"comma list (default: {','.join(SUITES)})")
    ap.add_argument("--attacks", default=",".join(ATTACKS),
                    help="comma list; '' runs only the no-attack baseline")
    ap.add_argument("--systems", default="typeguard,camel")
    ap.add_argument("--repeats", type=int, default=1,
                    help="repetitions per task (k); default 1 = pass@1")
    ap.add_argument("--max-workers", type=int, default=None,
                    help="parallel task evaluations; default ceil(n/4) so the "
                         "whole run takes about 4 sequential task-times")
    ap.add_argument("--timeout", type=int, default=TASK_TIMEOUT_S,
                    help="per-task budget in seconds (default 600, as in the paper)")
    ap.add_argument("--benchmark-version", default=BENCHMARK_VERSION)
    ap.add_argument("--plan-only", action="store_true",
                    help="print the plan and exit without running")
    ap.add_argument("--process-only", action="store_true",
                    help="skip execution; regenerate outputs from existing results")
    ap.add_argument("--yes", "-y", action="store_true",
                    help="skip the confirmation prompt")
    ap.add_argument("--no-build", action="store_true",
                    help="don't `cabal build` before resolving agent binaries")
    args = ap.parse_args()

    models = {m.name: m for m in map(Model.load, args.models)}
    suites = [s for s in args.suites.split(",") if s]
    attacks = [a for a in args.attacks.split(",") if a]
    systems = [s for s in args.systems.split(",") if s]
    logdir = Path(args.logdir).resolve()

    if not args.process_only:
        atoms = expand(list(models.values()), suites, attacks, args.repeats, systems)
        to_run, cached = split_cached(atoms, logdir, models)
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
            from execute import run_atoms

            report = run_atoms(to_run, models, logdir, args.benchmark_version,
                               args.timeout, max_workers, build=not args.no_build)
            print(f"\nRun finished: {report['completed']} completed, "
                  f"{report['timeout']} timed out, {len(report['crashed'])} crashed.")
            for atom, log in report["crashed"]:
                print(f"  CRASHED (no result): {atom}\n    worker log: {log}")

    from process import process

    process(logdir, models, suites, attacks, args.repeats)
    return 0


if __name__ == "__main__":
    sys.exit(main())
