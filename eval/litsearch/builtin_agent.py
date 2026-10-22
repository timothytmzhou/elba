"""A standard agent with Anthropic's built-in web search tool.

Claude Sonnet 5 through the Anthropic API with the server-side
web_search_20260209 tool. The only client tool is write_bib_file, which the
task requires. Nothing constrains what the agent writes to the bib file.

The client is chosen by environment: ANTHROPIC_API_KEY selects the
first-party API, otherwise ANTHROPIC_AWS_WORKSPACE_ID selects Claude
Platform on AWS with SigV4 credentials.
"""

from __future__ import annotations

import os
from pathlib import Path

MODEL_ID = "claude-sonnet-5"
MAX_TURNS = 40

SYSTEM_PROMPT = (
    "You are a helpful research assistant. Use the available tools to "
    "search the web and write the requested bibliography file."
)

TOOLS = [
    {"type": "web_search_20260209", "name": "web_search"},
    {"name": "write_bib_file",
     "description": "Write the given content to the bibliography file "
                    "named in the task. Overwrites the file.",
     "input_schema": {
         "type": "object",
         "properties": {"content": {"type": "string"}},
         "required": ["content"]}},
]


def make_client():
    if os.environ.get("ANTHROPIC_API_KEY"):
        import anthropic

        return anthropic.Anthropic()
    if os.environ.get("ANTHROPIC_AWS_WORKSPACE_ID"):
        from anthropic import AnthropicAWS

        return AnthropicAWS()
    raise RuntimeError("set ANTHROPIC_API_KEY or ANTHROPIC_AWS_WORKSPACE_ID")


def run_task(prompt: str, bib_path: Path, effort: str = "high") -> dict:
    """Run one task to completion. Returns the transcript and usage."""
    client = make_client()
    messages = [{"role": "user", "content": prompt}]
    usage = {"input": 0, "output": 0, "llm_calls": 0, "web_searches": 0}
    tool_log = []

    for _ in range(MAX_TURNS):
        response = client.messages.create(
            model=MODEL_ID,
            max_tokens=16000,
            system=SYSTEM_PROMPT,
            messages=messages,
            tools=TOOLS,
            thinking={"type": "adaptive"},
            output_config={"effort": effort})
        usage["input"] += response.usage.input_tokens
        usage["output"] += response.usage.output_tokens
        usage["llm_calls"] += 1
        server_use = getattr(response.usage, "server_tool_use", None)
        if server_use and getattr(server_use, "web_search_requests", None):
            usage["web_searches"] += server_use.web_search_requests
        messages.append({"role": "assistant", "content": response.content})

        if response.stop_reason == "pause_turn":
            continue
        if response.stop_reason != "tool_use":
            break

        tool_results = []
        for block in response.content:
            if block.type != "tool_use":
                continue
            if block.name == "write_bib_file":
                content = block.input["content"]
                bib_path.write_text(content)
                result = f"wrote {len(content)} characters to {bib_path.name}"
            else:
                result = f"unknown tool {block.name}"
            tool_log.append({"tool": block.name, "output": result})
            tool_results.append({"type": "tool_result",
                                 "tool_use_id": block.id,
                                 "content": result})
        messages.append({"role": "user", "content": tool_results})

    final_text = "".join(
        block.text for block in messages[-1]["content"]
        if getattr(block, "type", None) == "text") if messages[-1]["role"] == "assistant" else ""
    return {"usage": usage, "turns": usage["llm_calls"], "tools": tool_log,
            "final": final_text}
