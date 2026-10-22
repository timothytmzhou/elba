"""A standard tool-use agent on Bedrock Converse.

Claude Sonnet 5 with adaptive thinking, driven by the stock Converse tool
loop. Tools are the traditional web agent surface: web search, page fetch,
and a file write. Nothing constrains what the agent writes to the bib file.
"""

from __future__ import annotations

import html
import json
import re
import threading
import time
from pathlib import Path

import boto3
import botocore.config

AWS_REGION = "us-west-2"
MODEL_ID = "us.anthropic.claude-sonnet-5"
MAX_TURNS = 40
PAGE_CHAR_LIMIT = 15000

SYSTEM_PROMPT = (
    "You are a helpful research assistant. Use the available tools to "
    "search the web, read pages, and write the requested bibliography file."
)

TOOL_CONFIG = {"tools": [
    {"toolSpec": {
        "name": "web_search",
        "description": "Search the web. Returns the top results as a JSON "
                       "list of {title, url, snippet}.",
        "inputSchema": {"json": {
            "type": "object",
            "properties": {"query": {"type": "string"}},
            "required": ["query"]}}}},
    {"toolSpec": {
        "name": "fetch_page",
        "description": "Fetch a URL and return its visible text, truncated "
                       f"to {PAGE_CHAR_LIMIT} characters.",
        "inputSchema": {"json": {
            "type": "object",
            "properties": {"url": {"type": "string"}},
            "required": ["url"]}}}},
    {"toolSpec": {
        "name": "write_bib_file",
        "description": "Write the given content to the bibliography file "
                       "named in the task. Overwrites the file.",
        "inputSchema": {"json": {
            "type": "object",
            "properties": {"content": {"type": "string"}},
            "required": ["content"]}}}},
]}

# One search at a time process wide, DuckDuckGo throttles bursts.
_search_lock = threading.Lock()


def web_search(query: str) -> str:
    from ddgs import DDGS

    for attempt in range(4):
        try:
            with _search_lock:
                results = DDGS().text(query, max_results=10)
                time.sleep(1.0)
            rows = [{"title": r.get("title", ""), "url": r.get("href", ""),
                     "snippet": r.get("body", "")} for r in results]
            return json.dumps(rows)
        except Exception as e:  # noqa: BLE001 ddgs raises assorted types
            if attempt == 3:
                return f"search error: {e}"
            time.sleep(5 * (attempt + 1))
    return "search error"


def strip_html(page: str) -> str:
    page = re.sub(r"(?is)<(script|style|nav|header|footer).*?</\1>", " ", page)
    page = re.sub(r"(?s)<[^>]+>", " ", page)
    page = html.unescape(page)
    return re.sub(r"\s+", " ", page).strip()


def fetch_page(url: str) -> str:
    import requests

    try:
        resp = requests.get(url, timeout=20, headers={
            "User-Agent": "Mozilla/5.0 (research assistant; mailto:ttzhou@ucsd.edu)"})
        content_type = resp.headers.get("content-type", "")
        if "html" in content_type:
            text = strip_html(resp.text)
        else:
            text = resp.text
        return text[:PAGE_CHAR_LIMIT] or f"empty response (status {resp.status_code})"
    except Exception as e:  # noqa: BLE001
        return f"fetch error: {e}"


def run_tool(name: str, args: dict, bib_path: Path) -> str:
    if name == "web_search":
        return web_search(args["query"])
    if name == "fetch_page":
        return fetch_page(args["url"])
    if name == "write_bib_file":
        bib_path.write_text(args["content"])
        return f"wrote {len(args['content'])} characters to {bib_path.name}"
    return f"unknown tool {name}"


def run_task(prompt: str, bib_path: Path, effort: str = "high") -> dict:
    """Run one task to completion. Returns the transcript and usage."""
    timeouts = botocore.config.Config(read_timeout=1800, connect_timeout=10)
    bedrock = boto3.Session().client("bedrock-runtime", region_name=AWS_REGION,
                                     config=timeouts)
    messages = [{"role": "user", "content": [{"text": prompt}]}]
    usage = {"input": 0, "output": 0, "llm_calls": 0}
    tool_log = []

    for _ in range(MAX_TURNS):
        result = bedrock.converse(
            modelId=MODEL_ID,
            system=[{"text": SYSTEM_PROMPT}],
            messages=messages,
            toolConfig=TOOL_CONFIG,
            inferenceConfig={"maxTokens": 32000},
            additionalModelRequestFields={
                "thinking": {"type": "adaptive"},
                "output_config": {"effort": effort}})
        usage["input"] += result["usage"]["inputTokens"]
        usage["output"] += result["usage"]["outputTokens"]
        usage["llm_calls"] += 1
        message = result["output"]["message"]
        messages.append(message)
        if result["stopReason"] != "tool_use":
            break
        tool_results = []
        for block in message["content"]:
            if "toolUse" not in block:
                continue
            call = block["toolUse"]
            output = run_tool(call["name"], call["input"], bib_path)
            tool_log.append({"tool": call["name"], "args": call["input"],
                             "output_chars": len(output)})
            tool_results.append({"toolResult": {
                "toolUseId": call["toolUseId"],
                "content": [{"text": output}]}})
        messages.append({"role": "user", "content": tool_results})

    final_text = "".join(b.get("text", "") for b in messages[-1].get("content", [])
                         if isinstance(b, dict))
    return {"usage": usage, "turns": usage["llm_calls"], "tools": tool_log,
            "final": final_text, "messages": messages}
