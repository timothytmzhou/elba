"""Run one CaMeL task evaluation inside the CaMeL checkout environment.

    uv run --project camel --env-file camel/.env \
        python eval/camel_eval/worker.py '<atom json>'

Builds the pipeline with CaMeL's patched make_tools_pipeline and writes the
result in the standard AgentDojo layout.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from agentdojo.attacks.attack_registry import load_attack
from agentdojo.benchmark import run_task_with_injection_tasks, run_task_without_injection_tasks
from agentdojo.logging import OutputLogger
from agentdojo.task_suite.load_suites import get_suite

from camel.interpreter.interpreter import MetadataEvalMode
from camel.models import make_tools_pipeline


def main(spec: dict) -> None:
    logdir = Path(spec["logdir"])
    pipeline = make_tools_pipeline(
        spec["camel_model"],
        False,  # use_original
        False,  # replay_with_policies
        spec["attack"] if spec["attack"] != "none" else "important_instructions",
        spec.get("reasoning_effort") or "medium",
        None,  # thinking_budget_tokens
        spec["suite"],
        None,  # ad_defense
        MetadataEvalMode.NORMAL,
        None,  # q_llm
        no_policy=spec["variant"] == "nopolicy",
    )
    if pipeline.name != spec["pipeline_name"]:
        raise RuntimeError(f"pipeline name mismatch: CaMeL built {pipeline.name!r}, "
                           f"expected {spec['pipeline_name']!r}")

    suite = get_suite(spec["benchmark_version"], spec["suite"])
    task = suite.get_user_task_by_id(spec["task_id"])
    with OutputLogger(str(logdir)):
        if spec["attack"] == "none":
            utility, security = run_task_without_injection_tasks(
                suite, pipeline, task, logdir, force_rerun=False,
                benchmark_version=spec["benchmark_version"])
        else:
            attack = load_attack(spec["attack"], suite, pipeline)
            utility_results, security_results = run_task_with_injection_tasks(
                suite, pipeline, task, attack, logdir, force_rerun=False,
                injection_tasks=[spec["injection_task_id"]],
                benchmark_version=spec["benchmark_version"])
            (utility, security), = zip(utility_results.values(), security_results.values())
    print(f"[done] {spec['suite']}-{spec['task_id']}-{spec['attack']}-"
          f"{spec['injection_task_id']}: utility={utility} security={security}", flush=True)


if __name__ == "__main__":
    main(json.loads(sys.argv[1]))
