#!/usr/bin/env python3
"""Run the built-in web search baseline over the task set.

    python eval/litsearch/run_builtin.py [--limit N] [--workers K]

Writes logs/litsearch/builtin/<slug>/{task.txt,refs.bib,usage.json}.
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

import builtin_agent  # noqa: E402
from tasks import TOPICS, task_prompt  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = REPO_ROOT / "logs" / "litsearch" / "builtin"


def run_one(entry, effort: str) -> str:
    slug, topic, aspects = entry
    task_dir = OUT_ROOT / slug
    if (task_dir / "usage.json").exists():
        return "cached"
    task_dir.mkdir(parents=True, exist_ok=True)
    bib_path = task_dir / "refs.bib"
    prompt = task_prompt(topic, aspects, "refs.bib")
    (task_dir / "task.txt").write_text(prompt)
    try:
        report = builtin_agent.run_task(prompt, bib_path, effort)
    except Exception:
        (task_dir / "error.txt").write_text(traceback.format_exc())
        return "error"
    (task_dir / "summary.txt").write_text(report["final"])
    (task_dir / "usage.json").write_text(json.dumps(
        {"usage": report["usage"], "turns": report["turns"], "tools": report["tools"]}))
    return "done"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--limit", type=int, default=None, help="run only the first N tasks")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--effort", default="high")
    args = ap.parse_args()

    entries = TOPICS[: args.limit] if args.limit else TOPICS
    outcomes = thread_map(lambda e: run_one(e, args.effort), entries,
                          max_workers=args.workers)
    print({o: outcomes.count(o) for o in set(outcomes)})
    return 0


if __name__ == "__main__":
    sys.exit(main())
