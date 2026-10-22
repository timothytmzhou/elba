#!/usr/bin/env python3
"""Run the Elba litsearch agent over the task set.

    python eval/litsearch/run_elba.py [--limit N] [--workers K]

Each task runs the litsearch binary in its own directory with a private
LLM_USER_PATH, so token counts stay per task. Tasks with an existing
usage.json are skipped, so reruns resume.
"""

from __future__ import annotations

import argparse
import json
import os
import sqlite3
import subprocess
import sys
from pathlib import Path

from tqdm.contrib.concurrent import thread_map

sys.path.insert(0, str(Path(__file__).resolve().parent))

from tasks import TOPICS, task_prompt  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = REPO_ROOT / "logs" / "litsearch" / "elba"
TASK_TIMEOUT_S = 900

AGENT_CONFIG = {
    "modelName": "us.anthropic.claude-sonnet-5",
    "systemPrompt": "",
    "maxAttempts": 3,
    "maxDepth": 10,
    "seed": None,
    "reasoningEffort": "high",
    "llmCommand": None,
    "evalAdversarially": False,
}


def llm_token_usage(llm_user_dir: Path) -> dict | None:
    db = llm_user_dir / "logs.db"
    if not db.exists():
        return None
    with sqlite3.connect(db) as conn:
        row = conn.execute("SELECT COALESCE(SUM(input_tokens),0), "
                           "COALESCE(SUM(output_tokens),0), COUNT(*) FROM responses").fetchone()
    return {"input": row[0], "output": row[1], "llm_calls": row[2]}


def ghc_environment() -> str:
    # hint resolves packages through the cabal environment file, which GHC
    # only finds via cwd or this variable. Tasks run in their own directory.
    candidates = sorted(REPO_ROOT.glob(".ghc.environment.*"))
    if not candidates:
        raise RuntimeError("no .ghc.environment file, build with "
                           "--write-ghc-environment-files=always")
    return str(candidates[-1])


def run_one(entry, binary: str) -> str:
    slug, topic, aspects = entry
    task_dir = OUT_ROOT / slug
    if (task_dir / "usage.json").exists():
        return "cached"
    task_dir.mkdir(parents=True, exist_ok=True)
    prompt = task_prompt(topic, aspects, "refs.bib")
    (task_dir / "task.txt").write_text(prompt)
    (task_dir / "config.json").write_text(json.dumps(AGENT_CONFIG))
    llm_dir = task_dir / "llm"
    llm_dir.mkdir(exist_ok=True)
    env = dict(os.environ) | {"LLM_USER_PATH": str(llm_dir),
                              "GHC_ENVIRONMENT": ghc_environment()}
    cmd = [binary, "--task-file", "task.txt", "--config", "config.json",
           "--log-path", "agent.jsonl"]
    try:
        proc = subprocess.run(cmd, cwd=task_dir, env=env, timeout=TASK_TIMEOUT_S,
                              capture_output=True, text=True)
    except subprocess.TimeoutExpired:
        (task_dir / "error.txt").write_text(f"timeout after {TASK_TIMEOUT_S}s")
        return "timeout"
    (task_dir / "summary.txt").write_text(proc.stdout)
    outcome = "done" if proc.returncode == 0 else "failed"
    if proc.returncode != 0:
        (task_dir / "error.txt").write_text(proc.stderr)
    (task_dir / "usage.json").write_text(json.dumps(
        {"usage": llm_token_usage(llm_dir), "outcome": outcome}))
    return outcome


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=None, help="run only the first N tasks")
    ap.add_argument("--workers", type=int, default=8)
    ap.add_argument("--no-build", action="store_true")
    args = ap.parse_args()

    if not args.no_build:
        subprocess.run(["cabal", "build", "--write-ghc-environment-files=always",
                        "litsearch"], cwd=REPO_ROOT, check=True)
    binary = subprocess.check_output(["cabal", "list-bin", "litsearch"], cwd=REPO_ROOT,
                                     text=True).strip().splitlines()[-1]

    entries = TOPICS[: args.limit] if args.limit else TOPICS
    outcomes = thread_map(lambda e: run_one(e, binary), entries,
                          max_workers=args.workers)
    print({o: outcomes.count(o) for o in set(outcomes)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
