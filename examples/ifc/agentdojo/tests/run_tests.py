"""Runs the insecure and secure slack reference programs against agentdojo's slack suite over the JSONL bridge.

A run passes when agentdojo's utility check succeeds or a secure run ends blocked by IFC.

Usage:
    python run_tests.py                            # run all tests
    python run_tests.py ref-user_task_5            # run named tests
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from copy import deepcopy
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from agentdojo.functions_runtime import FunctionCall, FunctionsRuntime
from agentdojo.task_suite.load_suites import _SUITES, get_suite
from packaging.version import Version

sys.path.insert(0, str(Path(__file__).resolve().parents[4] / "eval"))

from bridge import to_jsonable  # noqa: E402

DEFAULT_SUITE = "slack"
NUM_USER_TASKS = 21


@dataclass(frozen=True)
class TestSpec:
    label: str
    exe_target: str
    argv: list[str]
    prompt: str
    # (bridge_ok, bridge_msg, pre_env, post_env, traces) -> (passed, note)
    assess: Callable[[bool, str, Any, Any, list[FunctionCall]], tuple[bool, str]]


def _latest_benchmark_version() -> str:
    return max(_SUITES.keys(), key=lambda v: Version(v.lstrip("v")))


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[4]


_exe_cache: dict[str, str] = {}


def _resolve_exe(target: str) -> str:
    """`cabal list-bin <target>` with a small cache."""
    if target in _exe_cache:
        return _exe_cache[target]
    cabal = shutil.which("cabal")
    if cabal is None:
        sys.exit("cabal not on PATH; cannot resolve target binaries")
    out = subprocess.check_output(
        [cabal, "list-bin", target],
        cwd=_repo_root(),
        text=True,
    )
    path = out.strip().splitlines()[-1]
    _exe_cache[target] = path
    return path


def _run_one(spec: TestSpec, runtime: FunctionsRuntime, env: Any) -> tuple[bool, str, list[FunctionCall]]:
    """Spawn the binary, speak the bridge, return (bridge_ok, bridge_msg, traces)."""
    exe_path = _resolve_exe(spec.exe_target)
    proc = subprocess.Popen(
        [exe_path, *spec.argv],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert proc.stdin is not None and proc.stdout is not None

    traces: list[FunctionCall] = []
    try:
        proc.stdin.write(json.dumps({"prompt": spec.prompt}) + "\n")
        proc.stdin.flush()
        while True:
            line = proc.stdout.readline()
            if not line:
                rc = proc.poll()
                return False, f"child closed stdout (exit code {rc})", traces
            msg = json.loads(line)
            if "call" in msg:
                method = msg["call"]
                args = msg.get("args") or {}
                if not isinstance(args, dict):
                    args = {}
                traces.append(FunctionCall(function=method, args=args))
                result, error = runtime.run_function(env, method, args)
                if error is None:
                    proc.stdin.write(json.dumps({"ok": to_jsonable(result)}) + "\n")
                else:
                    proc.stdin.write(json.dumps({"err": error}) + "\n")
                proc.stdin.flush()
            elif "done" in msg:
                return True, msg["done"], traces
            elif "failed" in msg:
                return False, msg["failed"], traces
            else:
                return False, f"unknown bridge message: {msg!r}", traces
    finally:
        try:
            proc.stdin.close()
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def _make_assess(task: Any, secure: bool) -> Callable[[bool, str, Any, Any, list[FunctionCall]], tuple[bool, str]]:
    # Blocked by IFC is an expected secure outcome.
    def assess(ok: bool, msg: str, pre: Any, post: Any, traces: list[FunctionCall]) -> tuple[bool, str]:
        if secure and ok and msg == "blocked by IFC":
            return True, "blocked by IFC (expected)"
        if not ok:
            return False, f"bridge error: {msg}"
        try:
            passed = task.utility(msg, pre, post)
        except NotImplementedError:
            passed = task.utility_from_traces(msg, pre, post, traces)
        return bool(passed), "" if passed else "utility=False"

    return assess


def _build_specs(suite: Any, prefix: str, target: str, secure: bool) -> list[TestSpec]:
    return [
        TestSpec(label=f"{prefix}-user_task_{i}", exe_target=target,
                 argv=["--task", f"user_task_{i}"],
                 prompt=suite.user_tasks[f"user_task_{i}"].PROMPT,
                 assess=_make_assess(suite.user_tasks[f"user_task_{i}"], secure))
        for i in range(NUM_USER_TASKS)
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", help="Test labels to run (default: all)")
    parser.add_argument("--benchmark-version", default=_latest_benchmark_version())
    args = parser.parse_args()

    suite = get_suite(args.benchmark_version, DEFAULT_SUITE)
    all_specs = (
        _build_specs(suite, "ref", "agentdojo-slack-reference", secure=False)
        + _build_specs(suite, "secref", "agentdojo-slack-secure-reference", secure=True)
    )
    by_label = {s.label: s for s in all_specs}

    if args.tests:
        selected = []
        for name in args.tests:
            if name not in by_label:
                sys.exit(f"unknown test label: {name}")
            selected.append(by_label[name])
    else:
        selected = all_specs

    passed_count = 0
    failed: list[str] = []
    for spec in selected:
        pre_env = suite.load_and_inject_default_environment({})
        post_env = deepcopy(pre_env)
        runtime = FunctionsRuntime(suite.tools)
        bridge_ok, bridge_msg, traces = _run_one(spec, runtime, post_env)
        passed, note = spec.assess(bridge_ok, bridge_msg, pre_env, post_env, traces)
        marker = "PASS" if passed else "FAIL"
        suffix = f": {note}" if note else ""
        print(f"  {marker}  {spec.label}{suffix}", flush=True)
        if passed:
            passed_count += 1
        else:
            failed.append(spec.label)

    print(f"\n{passed_count}/{len(selected)} tests passed", flush=True)
    if failed:
        print("Failed: " + ", ".join(failed), flush=True)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
