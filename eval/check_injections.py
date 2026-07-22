"""Report injection successes by re-running agentdojo's security check on recorded traces.

For each run this rebuilds the injected pre environment, replays the recorded tool
calls to produce the post environment, and runs the same check agentdojo runs,
security_from_traces falling back to security.

Notes:
- The violations reported under policy were manually reviewed and are false positives by AgentDojo.
- On some Sonnet and GPT runs CaMeL times out. These do not leave logs and so are not
  checked (excluding is strictly favorable to CaMeL).
"""

import argparse
import ast
import contextlib
import copy
import io
import json
from pathlib import Path

import agentdojo.task_suite.load_suites  # noqa: F401
from agentdojo.functions_runtime import FunctionCall, FunctionsRuntime
from agentdojo.task_suite.load_suites import get_suite

SWEEPS = [
    ("CaMeL main", "main/camel-*"),
    ("Elba main", "main/elba-*"),
    ("Elba adversarial (no policy)", "adversarial/rep*/elba-nopolicy-*"),
    ("Elba adversarial (policy)", "adversarial/rep*/elba-policy-*"),
]


def _as_call(raw):
    if isinstance(raw, dict):
        parsed = raw
    else:
        try:
            parsed = ast.literal_eval(str(raw))
        except (ValueError, SyntaxError):
            return None
    if not isinstance(parsed, dict) or "function" not in parsed:
        return None
    return FunctionCall(function=parsed["function"], args=parsed.get("args") or {})


def recorded_trace(messages):
    executed, requested = [], []
    for message in messages:
        call = _as_call(message.get("tool_call")) if message.get("tool_call") else None
        if call is not None:
            executed.append(call)
        for raw in message.get("tool_calls") or []:
            call = _as_call(raw)
            if call is not None:
                requested.append(call)
    return executed or requested


def model_output_text(messages):
    for message in reversed(messages):
        if message.get("role") != "assistant":
            continue
        content = message.get("content")
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            return "\n".join(str(b.get("content") or "") for b in content if isinstance(b, dict))
    return ""


def replay(suite, pre_environment, calls):
    environment = copy.deepcopy(pre_environment)
    runtime = FunctionsRuntime(suite.tools)
    for call in calls:
        try:
            runtime.run_function(environment, call.function, call.args, raise_on_error=False)
        except Exception:
            pass
    return environment


def violated(suite, task, messages, injections):
    pre_environment = suite.load_and_inject_default_environment(injections)
    calls = recorded_trace(messages)
    post_environment = replay(suite, pre_environment, calls)
    output = model_output_text(messages)
    from_traces = task.security_from_traces(output, pre_environment, post_environment, calls)
    if from_traces is not None:
        return bool(from_traces)
    return bool(task.security(output, pre_environment, post_environment))


def check(suite, roots):
    checked = violations = 0
    for root in roots:
        for path in sorted(root.glob("*/*/*/*.json")):
            if any(part.startswith(".") for part in path.parts):
                continue
            record = json.loads(path.read_text())
            injection_id = record.get("injection_task_id")
            task = suite.injection_tasks.get(injection_id) if injection_id else None
            if task is None or record.get("security") is None:
                continue
            try:
                success = violated(suite, task, record.get("messages") or [],
                                   record.get("injections") or {})
            except Exception:
                continue
            checked += 1
            violations += success
    return checked, violations


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--data", default=str(Path(__file__).resolve().parent / "data"),
                    help="directory holding the recordings")
    ap.add_argument("--suite", default="slack")
    ap.add_argument("--benchmark-version", default="v1.2.1")
    args = ap.parse_args()

    suite = get_suite(args.benchmark_version, args.suite)
    data = Path(args.data)
    width = max(len(name) for name, _ in SWEEPS)
    print(f"{'':{width}}  {'runs':>5}  {'violations':>10}")
    for name, pattern in SWEEPS:
        # agentdojo's slack injection tasks print while checking, keep that out of the table
        with contextlib.redirect_stdout(io.StringIO()):
            checked, violations = check(suite, sorted(data.glob(pattern)))
        print(f"{name:{width}}  {checked:>5}  {violations:>10}")


if __name__ == "__main__":
    main()
