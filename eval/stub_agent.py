#!/usr/bin/env python3
"""Scripted stand-in for the Haskell agent binary — lets the whole eval
pipeline (bridge, workers, parallel runner, processing) be tested without
LLM calls. Speaks the same line-JSON bridge protocol and takes the same
flags; the `--config` file supplies the script:

    {"actions": [{"call": "get_webpage", "args": {"url": "..."}},
                 {"sleep": 2},
                 {"done": "final answer"}]}

Tool errors are recorded and the script proceeds, so error paths can be
probed. Without an explicit done/failed, a default done is sent.
"""

import json
import sys
import time


def flag(name: str) -> str | None:
    argv = sys.argv
    return argv[argv.index(name) + 1] if name in argv else None


def send(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj) + "\n")
    sys.stdout.flush()


def main() -> int:
    actions = json.load(open(flag("--config"))).get("actions", []) if flag("--config") else []
    prompt = json.loads(sys.stdin.readline())["prompt"]
    transcript = [{"prompt": prompt}]
    ended = False
    for action in actions:
        if "sleep" in action:
            time.sleep(action["sleep"])
        elif "done" in action or "failed" in action:
            send(action)
            ended = True
            break
        else:
            send({"call": action["call"], "args": action.get("args", {})})
            transcript.append({"action": action, "reply": json.loads(sys.stdin.readline())})
    if not ended:
        send({"done": "stub agent finished"})
    if flag("--log-path"):
        with open(flag("--log-path"), "w") as f:
            for entry in transcript:
                f.write(json.dumps(entry) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
