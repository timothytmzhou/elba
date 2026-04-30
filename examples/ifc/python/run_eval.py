"""CLI for running the Haskell-backed agent against AgentDojo's slack suite.

Usage:
    # Sweep the whole suite (default) and print per-task + aggregate results:
    python run_eval.py

    # Run one task:
    python run_eval.py --user-task user_task_0

    # Override the binary (defaults to `cabal list-bin agentdojo-slack`):
    python run_eval.py --exe /path/to/agentdojo-slack
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

from packaging.version import Version

from agentdojo.benchmark import TaskResults, run_task_without_injection_tasks
from agentdojo.functions_runtime import FunctionCall  # noqa: F401  needed for the rebuild below
from agentdojo.logging import OutputLogger
from agentdojo.task_suite.load_suites import _SUITES, get_suite

# AgentDojo declares TaskResults with a forward reference to FunctionCall; the
# pydantic model isn't finalized until both are imported and rebuild() is called.
TaskResults.model_rebuild()

from haskell_agent import HaskellAgentPipeline  # noqa: E402  must follow rebuild

DEFAULT_SUITE = "slack"


def _latest_benchmark_version() -> str:
    """Pick the highest-numbered benchmark version installed in agentdojo."""
    return max(_SUITES.keys(), key=lambda v: Version(v.lstrip("v")))


def _default_exe_path() -> str:
    """Locate the agentdojo-slack binary via cabal list-bin."""
    cabal = shutil.which("cabal")
    if cabal is None:
        sys.exit("cabal not on PATH; pass --exe explicitly")
    out = subprocess.check_output(
        [cabal, "list-bin", "agentdojo-slack"],
        cwd=Path(__file__).resolve().parents[3],  # repo root
        text=True,
    )
    return out.strip().splitlines()[-1]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--user-task",
        default=None,
        help="Run a single user task (e.g. user_task_0). If omitted, sweeps every user task in the suite.",
    )
    parser.add_argument(
        "--exe",
        default=None,
        help="Path to the agentdojo-slack Haskell executable (auto-detected if absent)",
    )
    parser.add_argument(
        "--benchmark-version",
        default=_latest_benchmark_version(),
    )
    parser.add_argument(
        "--logdir",
        default=None,
        help="Optional directory to write per-task transcripts",
    )
    args = parser.parse_args()

    exe_path = args.exe or _default_exe_path()
    print(f"Using Haskell exe: {exe_path}", flush=True)

    suite = get_suite(args.benchmark_version, DEFAULT_SUITE)
    pipeline = HaskellAgentPipeline(exe_path)
    logdir = Path(args.logdir) if args.logdir else None

    if args.user_task is not None:
        task_ids = [args.user_task]
    else:
        task_ids = sorted(suite.user_tasks.keys())

    print(f"Running {len(task_ids)} task(s) on suite '{DEFAULT_SUITE}'...\n", flush=True)

    results: list[tuple[str, bool, bool]] = []
    with OutputLogger(logdir=str(logdir) if logdir else None):
        for task_id in task_ids:
            task = suite.get_user_task_by_id(task_id)
            try:
                utility, security = run_task_without_injection_tasks(
                    suite=suite,
                    agent_pipeline=pipeline,
                    task=task,
                    logdir=logdir,
                    force_rerun=True,
                    benchmark_version=args.benchmark_version,
                )
            except Exception as e:
                print(f"  {task_id}: CRASHED ({type(e).__name__}: {e})", flush=True)
                results.append((task_id, False, False))
                continue
            print(f"  {task_id}: utility={utility}  security={security}", flush=True)
            results.append((task_id, utility, security))

    passed = sum(1 for _, u, _ in results if u)
    total = len(results)
    print(f"\nUtility: {passed}/{total} passed", flush=True)
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
