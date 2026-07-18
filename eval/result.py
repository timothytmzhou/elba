"""One task evaluation's output, and the run tally."""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path


# Utility False with an error covers denials and timeouts.
@dataclass(frozen=True)
class Result:
    utility: bool
    security: bool
    duration_s: float | None = None
    tokens: dict | None = None
    error: str | None = None
    final_output: str | None = None
    messages: list = field(default_factory=list)
    agent_transcript: str | None = None
    result_file: str = ""


def load_result(path: Path) -> Result | None:
    try:
        r = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    if r.get("utility") not in (True, False):
        return None
    final = next((blk.get("content") or blk.get("text", "")
                  for m in reversed(r.get("messages") or [])
                  if m.get("role") == "assistant"
                  for blk in (m.get("content") or []) if isinstance(blk, dict)), None)
    return Result(r["utility"], r["security"], r.get("duration"), r.get("tokens"),
                  r.get("error"), final, r.get("messages") or [],
                  r.get("agent_transcript"), str(path))


class Outcome(Enum):
    COMPLETED = "completed"
    TIMEOUT = "timeout"


@dataclass(frozen=True)
class RunReport:
    completed: int = 0
    timeout: int = 0
