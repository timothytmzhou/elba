"""AgentDojo pipeline element that delegates the agent step to a Haskell binary.

The Haskell binary speaks newline-delimited JSON over its own stdin/stdout:

    Python -> Haskell (stdin):
        first line:        {"prompt": "..."}
        each subsequent:   {"ok": <value>}  or  {"err": "<message>"}

    Haskell -> Python (stdout):
        zero or more:      {"call": "<method>", "args": {...}}
        terminal:          {"done": "<final answer>"}
                       or  {"failed": "<error message>"}

Each `call` is dispatched via `runtime.run_function(env, method, args)` and the
result is sent back. Tool errors from AgentDojo (e.g. ValueError) become `err`
replies; `done`/`failed` end the loop.
"""

from __future__ import annotations

import json
import subprocess
import sys
from collections.abc import Sequence
from typing import Any

from agentdojo.agent_pipeline.base_pipeline_element import BasePipelineElement
from agentdojo.functions_runtime import EmptyEnv, Env, FunctionCall, FunctionsRuntime
from agentdojo.types import ChatAssistantMessage, ChatMessage, TextContentBlock


def _to_jsonable(obj: Any) -> Any:
    """Best-effort conversion of AgentDojo return values to JSON-friendly form."""
    if hasattr(obj, "model_dump"):
        return obj.model_dump()
    if isinstance(obj, (list, tuple)):
        return [_to_jsonable(x) for x in obj]
    if isinstance(obj, dict):
        return {k: _to_jsonable(v) for k, v in obj.items()}
    return obj


class HaskellAgentPipeline(BasePipelineElement):
    name = "haskell-agent"

    def __init__(self, exe_path: str, extra_args: list[str] | None = None) -> None:
        self.exe_path = exe_path
        self.extra_args = list(extra_args) if extra_args else []
        # Mutated by the driver (run_eval.py) before each task to point the
        # Haskell-side JSONL log at a per-task path; left as None to disable.
        self.log_path: str | None = None

    def query(
        self,
        query: str,
        runtime: FunctionsRuntime,
        env: Env = EmptyEnv(),
        messages: Sequence[ChatMessage] = [],
        extra_args: dict = {},
    ) -> tuple[str, FunctionsRuntime, Env, Sequence[ChatMessage], dict]:
        cmd = [self.exe_path, *self.extra_args]
        if self.log_path is not None:
            cmd += ["--log-path", self.log_path]
        # stderr is inherited so Haskell-side traces (the agents/Agents.hs debug
        # output of context + emitted code, plus crash dumps) appear directly in
        # the eval log.
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,  # line-buffered
        )
        assert proc.stdin is not None and proc.stdout is not None

        try:
            self._send(proc, {"prompt": query})
            answer, succeeded, tool_calls = self._loop(proc, runtime, env)
        except Exception:
            proc.kill()
            raise
        finally:
            proc.stdin.close()
            proc.wait(timeout=5)

        content_blocks = [TextContentBlock(type="text", content=answer)]
        new_messages = list(messages) + [
            ChatAssistantMessage(role="assistant", content=content_blocks, tool_calls=tool_calls)
        ]
        return answer, runtime, env, new_messages, extra_args

    def _send(self, proc: subprocess.Popen[str], obj: dict) -> None:
        assert proc.stdin is not None
        proc.stdin.write(json.dumps(obj, default=_to_jsonable) + "\n")
        proc.stdin.flush()

    def _loop(
        self,
        proc: subprocess.Popen[str],
        runtime: FunctionsRuntime,
        env: Env,
    ) -> tuple[str, bool, list[FunctionCall]]:
        assert proc.stdout is not None
        tool_calls: list[FunctionCall] = []
        while True:
            line = proc.stdout.readline()
            if not line:
                rc = proc.poll()
                raise RuntimeError(
                    f"Haskell child closed stdout before sending done/failed (exit code {rc})"
                )
            msg = json.loads(line)
            if "call" in msg:
                method = msg["call"]
                args = msg.get("args") or {}
                if not isinstance(args, dict):
                    args = {}
                tool_calls.append(FunctionCall(function=method, args=args))
                result, error = runtime.run_function(env, method, args)
                if error is None:
                    self._send(proc, {"ok": _to_jsonable(result)})
                else:
                    self._send(proc, {"err": error})
            elif "done" in msg:
                return msg["done"], True, tool_calls
            elif "failed" in msg:
                print(f"[haskell-agent failed] {msg['failed']}", file=sys.stderr, flush=True)
                return msg["failed"], False, tool_calls
            else:
                raise RuntimeError(f"Unknown message from Haskell child: {msg!r}")
