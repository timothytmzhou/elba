import os

import boto3
import llm
from llm_bedrock import AWS_REGION, BedrockModel


# The stock model plus the options the agent config passes, applied
# through additionalModelRequestFields. Text only, AWS chain auth only.
class ExtraBedrockModel(BedrockModel):
    class Options(llm.Options):
        seed: int | None = None
        reasoning_effort: str | None = None

    def execute(self, prompt, stream, response, conversation):
        bedrock = boto3.Session().client("bedrock-runtime", region_name=AWS_REGION)
        messages = []
        system = prompt.system
        for turn in conversation.responses if conversation else []:
            system = system or turn.prompt.system
            messages.append({"role": "user", "content": [{"text": turn.prompt.prompt}]})
            messages.append({"role": "assistant", "content": [{"text": turn.text_or_raise()}]})
        messages.append({"role": "user", "content": [{"text": prompt.prompt}]})
        params = {"messages": messages, "modelId": self.model_id}
        if system:
            params["system"] = [{"text": system}]
        fields = {k: v for k, v in prompt.options.model_dump().items() if v is not None}
        if fields:
            params["additionalModelRequestFields"] = fields
        result = bedrock.converse(**params)
        yield result["output"]["message"]["content"][-1]["text"]
        usage = result["usage"]
        response.set_usage(input=usage["inputTokens"], output=usage["outputTokens"])


# Registers the ids listed in LLM_BEDROCK_MODELS on top of the stock list.
@llm.hookimpl
def register_models(register):
    for model_id in filter(None, os.environ.get("LLM_BEDROCK_MODELS", "").split(",")):
        register(ExtraBedrockModel(model_id, False))
