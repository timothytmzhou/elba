#!/usr/bin/env python3
"""Run the full AgentDojo evaluation and produce the paper outputs.

    python eval/run.py --models eval/configs/*.json

Prints the plan, runs every remaining task evaluation in parallel, then
processes results into the raw dump and the LaTeX tables. Resumable.
Execution and processing are separate modules. See eval/README.md.
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
