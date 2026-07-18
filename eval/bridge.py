"""Speak the bridge protocol with a Haskell agent binary.

    Python to Haskell.  {"prompt": ...} then {"ok": ...} or {"err": ...}
    Haskell to Python.  {"call": ..., "args": {...}} then {"done"/"failed": ...}
"""

from __future__ import annotations

import datetime
import enum
import json
import os
import shutil
import subprocess
from pathlib import Path


def to_jsonable(obj):
    if hasattr(obj, "model_dump"):
        return obj.model_dump(mode="json")
    if isinstance(obj, (datetime.datetime, datetime.date, datetime.time)):
        return obj.isoformat()
    if isinstance(obj, enum.Enum):
        return to_jsonable(obj.value)
    if isinstance(obj, (list, tuple)):
        return [to_jsonable(x) for x in obj]
    if isinstance(obj, dict):
        return {k: to_jsonable(v) for k, v in obj.items()}
    return obj


class HaskellAgentPipeline:
    """AgentDojo pipeline element that runs one agent binary per query."""

    def __init__(self, cmd, name, config_path, log_path, llm_user_dir):
        self.cmd, self.name = cmd, name
        self.config_path, self.log_path = config_path, log_path
        self.llm_user_dir = llm_user_dir

    def _child_env(self) -> dict:
        # A private LLM_USER_PATH per agent keeps parallel llm conversations and token counts isolated.
        self.llm_user_dir.mkdir(parents=True, exist_ok=True)
        default = Path(os.environ.get("LLM_USER_PATH",
                                      Path.home() / ".config" / "io.datasette.llm"))
        if (default / "keys.json").exists() and not (self.llm_user_dir / "keys.json").exists():
            shutil.copy(default / "keys.json", self.llm_user_dir / "keys.json")
        return dict(os.environ) | {"LLM_USER_PATH": str(self.llm_user_dir)}

    def _send(self, proc, obj) -> None:
        proc.stdin.write(json.dumps(obj, default=to_jsonable) + "\n")
        proc.stdin.flush()

    def query(self, query, runtime, env=None, messages=(), extra_args={}):
        from agentdojo.functions_runtime import EmptyEnv, FunctionCall
        from agentdojo.logging import Logger
        from agentdojo.types import ChatAssistantMessage, ChatUserMessage, TextContentBlock

        env = env if env is not None else EmptyEnv()
        proc = subprocess.Popen(
            [*self.cmd, "--config", self.config_path, "--log-path", self.log_path],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, bufsize=1,
            env=self._child_env())
        tool_calls = []
        try:
            self._send(proc, {"prompt": query})
            while True:
                line = proc.stdout.readline()
                if not line:
                    raise RuntimeError(f"agent closed stdout early (exit {proc.poll()})")
                msg = json.loads(line)
                if "call" not in msg:
                    answer = msg.get("done") or msg.get("failed")
                    break
                args = msg.get("args") or {}
                tool_calls.append(FunctionCall(function=msg["call"], args=args))
                result, error = runtime.run_function(env, msg["call"], args)
                self._send(proc, {"err": error} if error else {"ok": to_jsonable(result)})
        finally:
            proc.stdin.close()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()

        new_messages = list(messages) + [
            ChatUserMessage(role="user", content=[TextContentBlock(type="text", content=query)]),
            ChatAssistantMessage(role="assistant", tool_calls=tool_calls,
                                 content=[TextContentBlock(type="text", content=answer)])]
        # log so the saved result carries the agent output
        Logger.get().log(new_messages)
        return answer, runtime, env, new_messages, extra_args
