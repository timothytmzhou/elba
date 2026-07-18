# Runs one benchmark on CaMeL inside the checkout venv where nopolicy is a fresh pass and policy replays it.
import os
import tempfile
from pathlib import Path

import anthropic
import camel.models
from camel.interpreter.interpreter import MetadataEvalMode

_upstream = camel.models._is_oai_reasoning_model
camel.models._is_oai_reasoning_model = lambda m: "gpt-5" in m or _upstream(m)


def _use_bedrock(bedrock_model: str) -> None:
    # Swaps in the Bedrock client under the upstream anthropic path and keeps the full model id upstream would truncate.
    os.environ.setdefault("ANTHROPIC_API_KEY", "unused-on-bedrock")
    base = camel.models.agent_pipeline.AnthropicLLM

    class BedrockAnthropicLLM(base):
        def __init__(self, client, model, **kwargs):
            super().__init__(anthropic.AsyncAnthropicBedrock(), bedrock_model, **kwargs)

    camel.models.agent_pipeline.AnthropicLLM = BedrockAnthropicLLM


def run_camel(bench, model, logdir, benchmark_version):
    from benchmark import result_path
    from run import run_agentdojo_task

    if model.camel_model.startswith("bedrock:"):
        _use_bedrock(model.camel_model.removeprefix("bedrock:"))
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
        MetadataEvalMode.NORMAL,
        None,  # q_llm
    )
    if replay:
        # the replayer reads recordings from a logs dir relative to cwd.
        tmp = tempfile.mkdtemp()
        os.symlink(os.path.join(str(logdir), f"rep{bench.rep}"), os.path.join(tmp, "logs"))
        os.chdir(tmp)
    run_agentdojo_task(bench, model, logdir, benchmark_version, pipeline)

    # camel writes under its own upstream pipeline name so copy it to ours.
    src = (Path(logdir) / f"rep{bench.rep}" / pipeline.name / bench.suite / bench.task_id
           / bench.attack / f"{bench.injection_task_id}.json")
    dst = result_path(bench, logdir)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(src.read_text())
