# The policy variant replays the recording the nopolicy variant wrote.
import json
import os
import tempfile
from pathlib import Path

# Fully initialize agentdojo before camel reaches into its suite submodules,
# otherwise camel's deep banking import hits a circular import.
import agentdojo.task_suite.load_suites  # noqa: F401

import anthropic
import openai
import camel.models
from camel.interpreter.interpreter import MetadataEvalMode

_upstream = camel.models._is_oai_reasoning_model
camel.models._is_oai_reasoning_model = lambda m: "gpt-5" in m or _upstream(m)


def _use_bedrock(bedrock_model: str) -> None:
    # Swaps Bedrock clients in under the upstream provider paths, keeping the full model id upstream would truncate.
    os.environ.setdefault("ANTHROPIC_API_KEY", "unused-on-bedrock")
    os.environ.setdefault("OPENAI_API_KEY", "unused-on-bedrock")
    anthropic_base = camel.models.agent_pipeline.AnthropicLLM
    openai_base = camel.models.agent_pipeline.OpenAILLM

    class BedrockAnthropicLLM(anthropic_base):
        def __init__(self, client, model, **kwargs):
            super().__init__(anthropic.AsyncAnthropicBedrock(), bedrock_model, **kwargs)
            # Claude 4.7+ reject the temperature parameter, None omits it
            self.temperature = None

    class BedrockOpenAILLM(openai_base):
        def __init__(self, client, model, *args, **kwargs):
            client = openai.OpenAI(
                base_url=f"https://bedrock-runtime.{os.environ['AWS_REGION']}.amazonaws.com/openai/v1",
                api_key=os.environ["AWS_BEARER_TOKEN_BEDROCK"])
            super().__init__(client, bedrock_model, *args, **kwargs)

    camel.models.agent_pipeline.AnthropicLLM = BedrockAnthropicLLM
    camel.models.agent_pipeline.OpenAILLM = BedrockOpenAILLM


def run_camel(bench, model, logdir, benchmark_version, bedrock=False):
    from benchmark import result_path
    from run import run_agentdojo_task

    if bedrock and model.bedrock_model:
        _use_bedrock(model.bedrock_model)
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
        MetadataEvalMode.STRICT,
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
            # The recorded nopolicy run was incomplete, e.g. it timed out, so
            # score the cell as a failure rather than leaving it missing.
            # security False means the attack was resisted, a pass, since an
            # agent that never converged never performed the injection.
            dst = result_path(bench, logdir)
            dst.parent.mkdir(parents=True, exist_ok=True)
            dst.write_text(json.dumps({"utility": False, "security": False,
                                       "error": f"replay of incomplete recording: {e}"}))
            return
    else:
        run_agentdojo_task(bench, model, logdir, benchmark_version, pipeline)

    # CaMeL writes under its own pipeline name, copy the result to ours.
    src = (Path(logdir) / f"rep{bench.rep}" / pipeline.name / bench.suite / bench.task_id
           / bench.attack / f"{bench.injection_task_id}.json")
    dst = result_path(bench, logdir)
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_text(src.read_text())
