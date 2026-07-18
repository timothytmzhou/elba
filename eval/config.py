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
    agent_config: AgentConfig
    camel_model: str | None = None  # None means typeguard only
    bedrock_model: str | None = None  # the Bedrock id, taken under --bedrock


def load_model(path: str | Path) -> Model:
    raw = json.loads(Path(path).read_text())
    extra = {k: raw.pop(k, None) for k in ("camel_model", "bedrock_model")}
    return Model(name=Path(path).stem, agent_config=AgentConfig(**raw), **extra)


# Models without a bedrock_model keep their API keys.
def on_bedrock(m: Model) -> Model:
    if not m.bedrock_model:
        return m
    return replace(m, agent_config=replace(m.agent_config, modelName=m.bedrock_model),
                   camel_model=m.camel_model and f"bedrock:{m.bedrock_model}")


def attack_persona(m: Model) -> str:
    name = m.agent_config.modelName.lower()
    if "claude" in name or "anthropic" in name:
        return "Claude"
    if "gpt" in name or "openai" in name:
        return "ChatGPT"
    return "AI assistant"


def display(m: Model) -> str:
    return " ".join(part.capitalize() for part in m.name.split("-")[:2])
