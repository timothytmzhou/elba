#!/usr/bin/env python3
"""Run the stock pydantic-ai baseline over the task set.

    python eval/litsearch/run_pai.py [--limit N] [--workers K]

The agent is a stock pydantic_ai.Agent on Bedrock with the framework's
packaged DuckDuckGo web search tool. The only task-specific tool is
write_bib_file, which the task requires. All model settings are framework
defaults.

Writes logs/litsearch/pai/<slug>/{task.txt,refs.bib,transcript.json,usage.json}.
Tasks with an existing usage.json are skipped, so reruns resume.
"""

from __future__ import annotations

import argparse
import json
import sys
import traceback
from pathlib import Path

from tqdm.contrib.concurrent import thread_map

sys.path.insert(0, str(Path(__file__).resolve().parent))

from tasks import TOPICS, task_prompt  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = REPO_ROOT / "logs" / "litsearch" / "pai"

SYSTEM_PROMPT = (
    "You are a helpful research assistant. Use the available tools to "
    "search the web and write the requested bibliography file."
)


def run_agent(prompt: str, bib_path: Path) -> dict:
    from pydantic_ai import Agent
    from pydantic_ai.common_tools.duckduckgo import duckduckgo_search_tool
    from pydantic_ai.usage import UsageLimits

    def write_bib_file(content: str) -> str:
        """Write the given content to the bibliography file named in the task.

        Overwrites the file.
        """
        bib_path.write_text(content)
        return f"wrote {len(content)} characters to {bib_path.name}"

    agent = Agent(
        "bedrock:us.anthropic.claude-sonnet-5",
        system_prompt=SYSTEM_PROMPT,
        tools=[duckduckgo_search_tool(), write_bib_file],
    )
    result = agent.run_sync(prompt, usage_limits=UsageLimits(request_limit=40))

    usage = result.usage() if callable(result.usage) else result.usage
    tokens = {"input": getattr(usage, "input_tokens", None) or getattr(usage, "request_tokens", 0),
              "output": getattr(usage, "output_tokens", None) or getattr(usage, "response_tokens", 0),
              "llm_calls": getattr(usage, "requests", 0)}
    try:
        from pydantic_core import to_jsonable_python

        transcript = to_jsonable_python(result.all_messages())
    except Exception:  # noqa: BLE001
        transcript = [str(m) for m in result.all_messages()]
    final = getattr(result, "output", None) or getattr(result, "data", "")
    return {"usage": tokens, "final": final, "transcript": transcript}


def run_one(entry) -> str:
    slug, topic, aspects = entry
    task_dir = OUT_ROOT / slug
    if (task_dir / "usage.json").exists():
        return "cached"
    task_dir.mkdir(parents=True, exist_ok=True)
    bib_path = task_dir / "refs.bib"
    prompt = task_prompt(topic, aspects, "refs.bib")
    (task_dir / "task.txt").write_text(prompt)
    try:
        report = run_agent(prompt, bib_path)
    except Exception:
        (task_dir / "error.txt").write_text(traceback.format_exc())
        return "error"
    (task_dir / "transcript.json").write_text(
        json.dumps(report["transcript"], default=str, indent=1))
    (task_dir / "summary.txt").write_text(str(report["final"]))
    (task_dir / "usage.json").write_text(json.dumps({"usage": report["usage"]}))
    return "done"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=None, help="run only the first N tasks")
    ap.add_argument("--workers", type=int, default=3)
    args = ap.parse_args()

    entries = TOPICS[: args.limit] if args.limit else TOPICS
    outcomes = thread_map(run_one, entries, max_workers=args.workers)
    print({o: outcomes.count(o) for o in set(outcomes)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
