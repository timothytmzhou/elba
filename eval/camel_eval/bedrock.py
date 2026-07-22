import os

import anthropic
import openai
import camel.models


def _fill_empty_text(messages):
    # Bedrock rejects empty text blocks so fill them like the llm-bedrock plugin
    for message in messages:
        content = message["content"]
        if isinstance(content, str):
            if not content.strip():
                message["content"] = "(no output)"
        else:
            message["content"] = [_fill_block(block) for block in content]
    return messages


def _fill_block(block):
    # A block is either an anthropic TextBlock object or a TextBlockParam dict
    if isinstance(block, dict):
        block_type = block.get("type")
        text = block.get("text")
    else:
        block_type = getattr(block, "type", None)
        text = getattr(block, "text", None)
    if block_type != "text" or (text and text.strip()):
        return block
    if isinstance(block, dict):
        return {**block, "text": "(no output)"}
    return block.model_copy(update={"text": "(no output)"})


def use_bedrock(bedrock_model: str, effort: str) -> None:
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
            # Opus 4.7 and 4.8 only think when adaptive is set explicitly
            # budget_tokens is rejected so effort rides in output_config
            stream = self.client.messages.stream

            def adaptive_stream(**kw):
                kw["thinking"] = {"type": "adaptive"}
                kw["max_tokens"] = max(kw.get("max_tokens") or 0, 32000)
                kw["extra_body"] = {**(kw.get("extra_body") or {}),
                                    "output_config": {"effort": effort}}
                kw["messages"] = _fill_empty_text(kw.get("messages") or [])
                return stream(**kw)

            self.client.messages.stream = adaptive_stream

    class BedrockOpenAILLM(openai_base):
        def __init__(self, client, model, *args, **kwargs):
            client = openai.OpenAI(
                base_url=f"https://bedrock-runtime.{os.environ['AWS_REGION']}.amazonaws.com/openai/v1",
                api_key=os.environ["AWS_BEARER_TOKEN_BEDROCK"])
            super().__init__(client, bedrock_model, *args, **kwargs)

    camel.models.agent_pipeline.AnthropicLLM = BedrockAnthropicLLM
    camel.models.agent_pipeline.OpenAILLM = BedrockOpenAILLM
