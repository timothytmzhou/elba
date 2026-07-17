"""Builds the CaMeL pipeline inside the checkout venv.

+camel is upstream's fresh no policy pass. +camel+secpol replays a recorded
+camel run with the suite's security policies, upstream's own methodology.
"""

import os
import tempfile

import camel.models
from camel.interpreter.interpreter import MetadataEvalMode

_upstream = camel.models._is_oai_reasoning_model
camel.models._is_oai_reasoning_model = lambda m: "gpt-5" in m or _upstream(m)


def make_pipeline(bench, logdir):
    replay = bench.variant == "policy"
    pipeline = camel.models.make_tools_pipeline(
        bench.model.camel_model,
        False,  # use_original
        replay,  # replay_with_policies
        bench.attack if bench.attack != "none" else "important_instructions",
        bench.model.agent_config.get("reasoningEffort") or "medium",
        None,  # thinking_budget_tokens
        bench.suite,
        None,  # ad_defense
        MetadataEvalMode.NORMAL,
        None,  # q_llm
    )
    if replay:
        # the replayer reads recordings from logs/ relative to cwd
        tmp = tempfile.mkdtemp()
        os.symlink(os.path.join(str(logdir), f"rep{bench.rep}"), os.path.join(tmp, "logs"))
        os.chdir(tmp)
    return pipeline
