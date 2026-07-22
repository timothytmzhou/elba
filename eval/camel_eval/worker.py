# The policy variant replays the recording the nopolicy variant wrote.
import json
import os
import tempfile
from pathlib import Path

# Fully initialize agentdojo before camel reaches into its suite submodules,
# otherwise camel's deep banking import hits a circular import.
import agentdojo.task_suite.load_suites  # noqa: F401

import camel.models
from camel.interpreter.interpreter import MetadataEvalMode

_upstream = camel.models._is_oai_reasoning_model
camel.models._is_oai_reasoning_model = lambda m: "gpt-5" in m or _upstream(m)


def run_camel(bench, model, logdir, benchmark_version, bedrock=False):
    from benchmark import result_path
    from camel_eval.bedrock import use_bedrock
    from run import run_agentdojo_task

    if bedrock and model.bedrock_model:
        use_bedrock(model.bedrock_model, model.agent_config.reasoningEffort or "high")
    replay = bench.variant == "policy"
    pipeline = camel.models.make_tools_pipeline(
        model.camel_model,
        False,  # use_original
        replay,  # replay_with_policies
        bench.attack if bench.attack != "none" else "important_instructions",
        model.agent_config.reasoningEffort or "medium",
        None,  # thinking_budget_tokens
        bench.suite,
        None,  # ad_defense
        MetadataEvalMode.NORMAL if os.environ.get("CAMEL_EVAL_MODE") == "NORMAL"
        else MetadataEvalMode.STRICT,
        None,  # q_llm
    )
    if replay:
        # The replayer reads recordings from a logs dir relative to cwd.
        tmp = tempfile.mkdtemp()
        os.symlink(os.path.join(str(logdir), f"rep{bench.rep}"), os.path.join(tmp, "logs"))
        os.chdir(tmp)
        try:
            run_agentdojo_task(bench, model, logdir, benchmark_version, pipeline)
        except Exception as e:
            dst = result_path(bench, logdir)
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(json.dumps({"utility": False, "security": False,
                                       "error": f"replay of incomplete recording: {e}"}))
            return
    else:
        try:
            run_agentdojo_task(bench, model, logdir, benchmark_version, pipeline)
        except Exception as e:
            dst = result_path(bench, logdir)
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(json.dumps({"utility": False, "security": False,
                                       "error": f"agent crashed: {e}"}))
            return

    # CaMeL writes under its own pipeline name, copy the result to ours.
    src = (Path(logdir) / f"rep{bench.rep}" / pipeline.name / bench.suite / bench.task_id
           / bench.attack / f"{bench.injection_task_id}.json")
    dst = result_path(bench, logdir)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(src.read_text())
