"""Driver for the slack IFC tests.

Each test is a named entry point in the `slack-tests` Haskell binary
(see Tests.hs). For each test, this script:

  1. Loads a fresh copy of AgentDojo's slack environment.
  2. Spawns `slack-tests <test-name>` as a subprocess.
  3. Speaks the same JSONL bridge protocol as `haskell_agent.py`,
     dispatching `call` messages to AgentDojo's `runtime.run_function`.
  4. Reads the terminal `done` / `failed` and prints PASS / FAIL.

No LLM is involved. The test binary itself decides whether each test
"passed" by checking if the IFC outcome matches the expectation
encoded in the test name (`pass-*` vs `fail-*`).

Usage:
    python run_tests.py                      # run all tests
    python run_tests.py pass-simple-send ... # run named tests
    python run_tests.py --exe /path/to/exe   # override binary path
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any

from agentdojo.functions_runtime import FunctionsRuntime
from agentdojo.task_suite.load_suites import _SUITES, get_suite
from packaging.version import Version

DEFAULT_SUITE = "slack"

ALL_TESTS = [
    "pass-simple-send",
    "pass-forward-labeled",
    "pass-tolabeled-web-slack",
    "pass-tolabeled-web-web",
    "fail-unlabel-then-send",
    "fail-web-read-then-slack",
    "fail-unlabel-slack-post-web",
    "fail-web-read-then-post",
]


def _to_jsonable(obj: Any) -> Any:
    if hasattr(obj, "model_dump"):
        return obj.model_dump()
    if isinstance(obj, (list, tuple)):
        return [_to_jsonable(x) for x in obj]
    if isinstance(obj, dict):
        return {k: _to_jsonable(v) for k, v in obj.items()}
    return obj


def _latest_benchmark_version() -> str:
    return max(_SUITES.keys(), key=lambda v: Version(v.lstrip("v")))


def _default_exe_path() -> str:
    cabal = shutil.which("cabal")
    if cabal is None:
        sys.exit("cabal not on PATH; pass --exe explicitly")
    out = subprocess.check_output(
        [cabal, "list-bin", "slack-tests"],
        cwd=Path(__file__).resolve().parents[3],  # repo root
        text=True,
    )
    return out.strip().splitlines()[-1]


def _run_one(exe_path: str, test_name: str, runtime: FunctionsRuntime, env: Any) -> tuple[bool, str]:
    """Run a single test and return (passed, message)."""
    proc = subprocess.Popen(
        [exe_path, test_name],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        text=True,
        bufsize=1,
    )
    assert proc.stdin is not None and proc.stdout is not None

    try:
        # The bridge expects a prompt line first; tests don't use it.
        proc.stdin.write(json.dumps({"prompt": ""}) + "\n")
        proc.stdin.flush()
        while True:
            line = proc.stdout.readline()
            if not line:
                rc = proc.poll()
                return False, f"child closed stdout (exit code {rc})"
            msg = json.loads(line)
            if "call" in msg:
                method = msg["call"]
                args = msg.get("args") or {}
                if not isinstance(args, dict):
                    args = {}
                result, error = runtime.run_function(env, method, args)
                if error is None:
                    proc.stdin.write(json.dumps({"ok": _to_jsonable(result)}) + "\n")
                else:
                    proc.stdin.write(json.dumps({"err": error}) + "\n")
                proc.stdin.flush()
            elif "done" in msg:
                # The Haskell test reports its own outcome via `done` on
                # success and `failed` on outcome-mismatch.
                return True, msg["done"]
            elif "failed" in msg:
                return False, msg["failed"]
            else:
                return False, f"unknown bridge message: {msg!r}"
    finally:
        try:
            proc.stdin.close()
        except Exception:
            pass
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tests", nargs="*", help="Tests to run (default: all)")
    parser.add_argument("--exe", default=None, help="Path to slack-tests binary")
    parser.add_argument("--benchmark-version", default=_latest_benchmark_version())
    args = parser.parse_args()

    exe_path = args.exe or _default_exe_path()
    print(f"Using test binary: {exe_path}\n", flush=True)

    suite = get_suite(args.benchmark_version, DEFAULT_SUITE)
    tests = args.tests or ALL_TESTS

    passed_count = 0
    failed: list[str] = []
    for test_name in tests:
        # Fresh env per test so state doesn't leak across tests.
        env = suite.load_and_inject_default_environment({})
        runtime = FunctionsRuntime(suite.tools)
        ok, msg = _run_one(exe_path, test_name, runtime, env)
        marker = "PASS" if ok else "FAIL"
        print(f"  {marker}  {test_name}: {msg}", flush=True)
        if ok:
            passed_count += 1
        else:
            failed.append(test_name)

    print(f"\n{passed_count}/{len(tests)} tests passed", flush=True)
    if failed:
        print("Failed: " + ", ".join(failed), flush=True)
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
