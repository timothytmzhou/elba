from __future__ import annotations

import json
from dataclasses import dataclass, replace
from pathlib import Path


# Mirrors the Haskell Config record.
@dataclass(frozen=True)
class AgentConfig:
    modelName: str
    systemPrompt: str = ""
    maxAttempts: int = 3
    maxDepth: int = 10
    seed: int | None = None
    reasoningEffort: str | None = None
    llmCommand: str | None = None


@dataclass(frozen=True)
class Model:
    name: str
    provider: str
    agent_config: AgentConfig
    camel_model: str | None = None  # None means typeguard only
    bedrock_model: str | None = None  # the Bedrock id, taken under --bedrock


# The providers upstream CaMeL implements.
CAMEL_PROVIDERS = {"openai", "anthropic", "google"}


# The model field is provider:id, the pydantic ai format.
def load_model(path: str | Path) -> Model:
    raw = json.loads(Path(path).read_text())
    provider, _, model_id = raw.pop("model").partition(":")
    if not model_id:
        raise ValueError(f"model must look like provider:id in {path}")
    bedrock_model = raw.pop("bedrock_model", None)
    return Model(name=Path(path).stem, provider=provider,
                 agent_config=AgentConfig(modelName=model_id, **raw),
                 camel_model=f"{provider}:{model_id}" if provider in CAMEL_PROVIDERS else None,
                 bedrock_model=bedrock_model)


# Models without a bedrock_model keep their API keys.
def on_bedrock(m: Model) -> Model:
    if not m.bedrock_model:
        return m
    return replace(m, agent_config=replace(m.agent_config, modelName=m.bedrock_model),
                   camel_model=m.camel_model and f"bedrock:{m.bedrock_model}")


def attack_persona(m: Model) -> str:
    return {"anthropic": "Claude", "openai": "ChatGPT"}.get(m.provider, "AI assistant")


def display(m: Model) -> str:
    return " ".join(part.capitalize() for part in m.name.split("-")[:2])
