#!/usr/bin/env python3
"""Aggregate verification results into the rebuttal table.

    python eval/litsearch/tables.py [--systems pai,elba] [--logdir logs/litsearch]

Reads <logdir>/verify/entries.csv plus per task usage.json files and prints a
summary DataFrame and its LaTeX rendering. Manual adjudications of entries the
registries could not decide live in adjudications.json next to this script and
override the automated verdict.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

import pandas as pd

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]


def load_entries(verify_dir: Path) -> pd.DataFrame:
    df = pd.read_csv(verify_dir / "entries.csv", keep_default_na=False)
    adjudications_path = HERE / "adjudications.json"
    if adjudications_path.exists():
        for adj in json.loads(adjudications_path.read_text()):
            mask = ((df["system"] == adj["system"]) & (df["task"] == adj["task"])
                    & (df["key"] == adj["key"]))
            df.loc[mask, "verdict"] = adj["verdict"]
            if "errors" in adj:
                df.loc[mask, "errors"] = adj["errors"]
    return df


def task_stats(logdir: Path, system: str) -> dict:
    usage_files = sorted((logdir / system).glob("*/usage.json"))
    tokens_out = 0
    llm_calls = 0
    for path in usage_files:
        usage = json.loads(path.read_text()).get("usage") or {}
        tokens_out += usage.get("output", 0) or 0
        llm_calls += usage.get("llm_calls", 0) or 0
    return {"tasks_run": len(usage_files), "output_tokens": tokens_out,
            "llm_calls": llm_calls}


DISPLAY = {"pai": "Baseline (pydantic-ai)", "elba": "Elba",
           "baseline-custom": "Baseline (custom loop)"}


def summarize(df: pd.DataFrame, logdir: Path, systems: list[str]) -> pd.DataFrame:
    rows = []
    for system in systems:
        mine = df[df["system"] == system]
        n = len(mine)
        stats = task_stats(logdir, system)
        fabricated = int((mine["verdict"] == "fabricated").sum())
        wrong = int((mine["verdict"] == "wrong_fields").sum())
        unverified = int((mine["verdict"] == "unverified").sum())
        rows.append({
            "system": DISPLAY.get(system, system),
            "tasks": stats["tasks_run"],
            "tasks with bib": mine["task"].nunique(),
            "entries": n,
            "fabricated": f"{fabricated}/{n}",
            "wrong fields": f"{wrong}/{n}",
            "hallucinated": f"{fabricated + wrong}/{n}",
            "unverified": unverified,
            "llm calls": stats["llm_calls"],
            "output tokens": stats["output_tokens"],
        })
    return pd.DataFrame(rows).set_index("system")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--logdir", default=str(REPO_ROOT / "logs" / "litsearch"))
    ap.add_argument("--systems", default="pai,elba")
    args = ap.parse_args()

    logdir = Path(args.logdir)
    df = load_entries(logdir / "verify")
    table = summarize(df, logdir, args.systems.split(","))
    print(table.to_string())
    print()
    print(table.to_latex())
    return 0


if __name__ == "__main__":
    sys.exit(main())
