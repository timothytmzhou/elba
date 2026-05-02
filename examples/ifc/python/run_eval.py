"""CLI for running the Haskell-backed agent against AgentDojo's slack suite.

Mirrors `agentdojo/scripts/benchmark.py`: dispatches to AgentDojo's own
`benchmark_suite_*injections` functions so we stay close to parity with the
canonical eval. Use `--attack <name>` to run prompt-injection attacks; omit
it for the no-injection baseline.

Usage:
    # No-injection baseline over the whole suite:
    python run_eval.py --logdir logs/

    # Run one task, no attack:
    python run_eval.py --user-task user_task_0 --logdir logs/

    # Full sweep with the AgentDojo paper's primary attack:
    python run_eval.py --attack important_instructions --logdir logs/

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

from agentdojo.attacks.attack_registry import load_attack
from agentdojo.benchmark import (
    SuiteResults,
    TaskResults,
    benchmark_suite_with_injections,
    benchmark_suite_without_injections,
)
from agentdojo.functions_runtime import FunctionCall  # noqa: F401  needed for the rebuild below
from agentdojo.logging import OutputLogger
from agentdojo.models import MODEL_NAMES
from agentdojo.task_suite.load_suites import _SUITES, get_suite

# `important_instructions`-family attacks substring-match pipeline.name
# against MODEL_NAMES to pick a model identifier to embed in the
# injection text. Our pipeline.name is "haskell-agent", so register it.
MODEL_NAMES.setdefault("haskell-agent", "AI assistant")

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


def _print_results(results: SuiteResults, with_attack: bool) -> int:
    for (uid, iid), util in sorted(results["utility_results"].items()):
        sec = results["security_results"][(uid, iid)]
        label = f"{uid} / {iid}" if iid else uid
        print(f"  {label}: utility={util}  security={sec}", flush=True)

    util = list(results["utility_results"].values())
    sec = list(results["security_results"].values())
    print(f"\nUtility: {sum(util)}/{len(util)} passed", flush=True)
    if with_attack:
        # AgentDojo's predicate returns True when the attack succeeded;
        # "not exploited" is the complement.
        print(f"Security: {len(sec) - sum(sec)}/{len(sec)} not exploited", flush=True)
    return 0 if all(util) else 1


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--user-task",
        action="append",
        default=[],
        help="Filter user tasks (repeatable, e.g. --user-task user_task_0). Defaults to all.",
    )
    parser.add_argument(
        "--attack",
        default=None,
        help="Attack name (e.g. important_instructions). Omit for the no-injection baseline.",
    )
    parser.add_argument(
        "--injection-task",
        action="append",
        default=[],
        help="Filter injection tasks (repeatable). Only meaningful with --attack.",
    )
    parser.add_argument(
        "--no-force-rerun",
        action="store_true",
        help="Reuse cached per-task results in <logdir> instead of re-running.",
    )
    parser.add_argument(
        "--exe",
        default=None,
        help="Path to the agentdojo-slack Haskell executable (auto-detected if absent)",
    )
    parser.add_argument(
        "--config",
        default=None,
        help="Path to JSON Config file (forwarded to the Haskell binary as --config)",
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
    extra_args = ["--config", args.config] if args.config else []
    pipeline = HaskellAgentPipeline(exe_path, extra_args=extra_args)
    logdir = Path(args.logdir) if args.logdir else None

    force_rerun = not args.no_force_rerun

    if logdir is not None:
        agent_log_dir = logdir / pipeline.name
        agent_log_dir.mkdir(parents=True, exist_ok=True)
        pipeline.log_path = str(agent_log_dir / "agent.log")
        if force_rerun:
            # Resume runs (--no-force-rerun) keep the existing log so the
            # accumulated transcript across resumed sessions stays available.
            Path(pipeline.log_path).unlink(missing_ok=True)

    user_tasks = args.user_task or None
    injection_tasks = args.injection_task or None

    if args.attack is None:
        print(f"Running suite '{DEFAULT_SUITE}' (no attack)\n", flush=True)
    else:
        print(f"Running suite '{DEFAULT_SUITE}' with attack '{args.attack}'\n", flush=True)

    with OutputLogger(str(logdir) if logdir else None):
        if args.attack is None:
            results = benchmark_suite_without_injections(
                pipeline,
                suite,
                user_tasks=user_tasks,
                logdir=logdir,
                force_rerun=force_rerun,
                benchmark_version=args.benchmark_version,
            )
        else:
            attacker = load_attack(args.attack, suite, pipeline)
            results = benchmark_suite_with_injections(
                pipeline,
                suite,
                attacker,
                user_tasks=user_tasks,
                injection_tasks=injection_tasks,
                logdir=logdir,
                force_rerun=force_rerun,
                benchmark_version=args.benchmark_version,
            )

    return _print_results(results, with_attack=args.attack is not None)


if __name__ == "__main__":
    sys.exit(main())
