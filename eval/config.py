"""Model configs, loaded from configs/*.json."""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path


# Mirrors the Haskell Config record written out as the binary config json.
@dataclass(frozen=True)
class AgentConfig:
    modelName: str
    systemPrompt: str = ""
    maxAttempts: int = 3
    maxDepth: int = 10
    seed: int | None = None
    reasoningEffort: str | None = None
    llmCommand: str | None = None


# A None camel_model means only typeguard can run this model.
@dataclass(frozen=True)
class Model:
    name: str
    agent_config: AgentConfig
    camel_model: str | None = None


def load_model(path: str | Path) -> Model:
    raw = json.loads(Path(path).read_text())
    camel_model = raw.pop("camel_model", None)
    return Model(name=Path(path).stem, agent_config=AgentConfig(**raw), camel_model=camel_model)


# The persona the injection attack impersonates.
def attack_persona(m: Model) -> str:
    name = m.agent_config.modelName.lower()
    if "claude" in name or "anthropic" in name:
        return "Claude"
    if "gpt" in name or "openai" in name:
        return "ChatGPT"
    return "AI assistant"


def display(m: Model) -> str:
    return " ".join(part.capitalize() for part in m.name.split("-")[:2])
