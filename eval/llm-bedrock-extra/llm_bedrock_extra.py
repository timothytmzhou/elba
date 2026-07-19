import os

import llm
from llm_bedrock import BedrockModel


# Registers the ids listed in LLM_BEDROCK_MODELS on top of the stock list.
@llm.hookimpl
def register_models(register):
    for model_id in filter(None, os.environ.get("LLM_BEDROCK_MODELS", "").split(",")):
        register(BedrockModel(model_id, True))
