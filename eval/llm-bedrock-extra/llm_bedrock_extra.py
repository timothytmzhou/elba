import os

import boto3
import botocore.config
import llm
import openai
from aws_bedrock_token_generator import provide_token
from llm_bedrock import AWS_REGION, BedrockModel


# The stock model plus reasoning effort, which Claude takes as adaptive
# thinking with an output_config effort level.
class ConverseModel(BedrockModel):
    class Options(llm.Options):
        reasoning_effort: str | None = None

    def execute(self, prompt, stream, response, conversation):
        # long reasoning responses outlive the default 60s read timeout
        timeouts = botocore.config.Config(read_timeout=1800, connect_timeout=10)
        bedrock = boto3.Session().client("bedrock-runtime", region_name=AWS_REGION,
                                         config=timeouts)
        messages = []
        system = prompt.system
        for turn in conversation.responses if conversation else []:
            system = system or turn.prompt.system
            messages.append({"role": "user", "content": [{"text": turn.prompt.prompt}]})
            # Converse rejects empty text blocks
            text = turn.text_or_raise() or "(no output)"
            messages.append({"role": "assistant", "content": [{"text": text}]})
        messages.append({"role": "user", "content": [{"text": prompt.prompt}]})
        # the default 4096 cap gets fully consumed by thinking
        params = {"messages": messages, "modelId": self.model_id,
                  "inferenceConfig": {"maxTokens": 100000}}
        if system:
            params["system"] = [{"text": system}]
        if prompt.options.reasoning_effort:
            params["additionalModelRequestFields"] = {
                "thinking": {"type": "adaptive"},
                "output_config": {"effort": prompt.options.reasoning_effort}}
        result = bedrock.converse(**params)
        # reasoning responses interleave reasoningContent blocks with text
        blocks = result["output"]["message"]["content"]
        yield "".join(b["text"] for b in blocks if "text" in b)
        usage = result["usage"]
        response.set_usage(input=usage["inputTokens"], output=usage["outputTokens"])


# OpenAI models on Bedrock are served only by the OpenAI compatible
# mantle endpoint and its Responses API, with a token from the AWS chain.
class MantleModel(llm.Model):
    can_stream = False

    class Options(llm.Options):
        seed: int | None = None  # accepted for config compatibility, the Responses API has no seed
        reasoning_effort: str | None = None

    def __init__(self, model_id):
        self.model_id = model_id

    def execute(self, prompt, stream, response, conversation):
        client = openai.OpenAI(
            base_url=f"https://bedrock-mantle.{AWS_REGION}.api.aws/openai/v1",
            api_key=provide_token())
        messages = []
        system = prompt.system
        for turn in conversation.responses if conversation else []:
            system = system or turn.prompt.system
            messages.append({"role": "user", "content": turn.prompt.prompt})
            messages.append({"role": "assistant", "content": turn.text_or_raise()})
        messages.append({"role": "user", "content": prompt.prompt})
        if system:
            messages.insert(0, {"role": "system", "content": system})
        kwargs = {"model": self.model_id, "input": messages}
        if prompt.options.reasoning_effort:
            kwargs["reasoning"] = {"effort": prompt.options.reasoning_effort}
        result = client.responses.create(**kwargs)
        yield result.output_text
        response.set_usage(input=result.usage.input_tokens, output=result.usage.output_tokens)

    def __str__(self):
        return "Bedrock: {}".format(self.model_id)


# Registers the ids listed in LLM_BEDROCK_MODELS on top of the stock list.
# An openai. id is a mantle model, the rest go through Converse.
@llm.hookimpl
def register_models(register):
    for model_id in filter(None, os.environ.get("LLM_BEDROCK_MODELS", "").split(",")):
        if model_id.startswith("openai."):
            register(MantleModel(model_id))
        else:
            register(ConverseModel(model_id, True))
