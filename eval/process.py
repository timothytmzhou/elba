"""Turn the result tree into dump.jsonl and the LaTeX tables under <logdir>/results."""

from __future__ import annotations

import math
from pathlib import Path

import pandas as pd
from scipy.stats import binomtest

from benchmark import BENIGN, Benchmark, pipeline_name
from config import Model, display
from result import load_result

SYSTEM_LABELS = {
    ("typeguard", "policy"): "TypeGuard",
    ("typeguard", "nopolicy"): "TypeGuard (no policy)",
    ("camel", "policy"): "CaMeL",
    ("camel", "nopolicy"): "CaMeL (no policy)",
}
SYSTEM_ORDER = list(SYSTEM_LABELS.values())
ATTACK_LABELS = {"direct": "Direct", "important_instructions": r"Imp.\ Instr.",
                 "tool_knowledge": "Tool Instr."}
ATTACKS = list(ATTACK_LABELS)


# One row per task evaluation, with the model and system order fixed as categoricals.
def load_frame(logdir: Path, models: dict[str, Model]) -> pd.DataFrame:
    rows = []
    # A single repetition is stored flat, without the rep1 directory.
    for rep_dir in sorted(logdir.glob("rep*")) or [logdir]:
        rep = int(rep_dir.name[3:]) if rep_dir.name.startswith("rep") else 1
        for model in models.values():
            for system, variant in SYSTEM_LABELS:
                stem = Benchmark(system, variant, model.name, rep, "", "")
                for path in sorted((rep_dir / pipeline_name(stem)).glob("*/*/*/*.json")):
                    result = load_result(path)
                    if result is None:
                        continue
                    rows.append({
                        "System": SYSTEM_LABELS[(system, variant)],
                        "Model": display(model),
                        "system": system, "variant": variant,
                        "suite": path.parts[-4], "task": path.parts[-3],
                        "attack": path.parts[-2], "injection": path.stem, "rep": rep,
                        "utility": int(result.utility), "security": int(result.security),
                    })
    df = pd.DataFrame(rows)
    if df.empty:
        return df
    df["System"] = pd.Categorical(df["System"], categories=SYSTEM_ORDER, ordered=True)
    df["Model"] = pd.Categorical(df["Model"], categories=[display(m) for m in models.values()],
                                 ordered=True)
    return df


# A "wins/total" string per (System, Model) cell with one column per attack.
def _grid(sub: pd.DataFrame, wins: pd.Series, columns: list[str]) -> pd.DataFrame:
    total = sub.groupby(["System", "Model", "attack"], observed=True).size()
    cell = wins.astype(int).astype(str) + "/" + total.astype(int).astype(str)
    wide = cell.unstack("attack").reindex(columns=columns).sort_index()
    wide = wide.rename(columns={BENIGN: "Safe", **ATTACK_LABELS})
    wide.columns.name = None
    return wide


def utility_frame(df: pd.DataFrame, suite: str) -> pd.DataFrame:
    sub = df[(df["suite"] == suite) & df["attack"].isin([BENIGN] + ATTACKS)]
    completed = sub.groupby(["System", "Model", "attack"], observed=True)["utility"].sum()
    return _grid(sub, completed, [BENIGN] + ATTACKS)


def security_frame(df: pd.DataFrame, suite: str) -> pd.DataFrame:
    sub = df[(df["suite"] == suite) & df["attack"].isin(ATTACKS)]
    grp = sub.groupby(["System", "Model", "attack"], observed=True)
    resisted = grp.size() - grp["security"].sum()  # security True means the attack won
    return _grid(sub, resisted, ATTACKS)


def adversarial_frame(df: pd.DataFrame, suite: str) -> pd.DataFrame:
    sub = df[(df["suite"] == suite) & (df["attack"] == "adversarial") & (df["system"] == "typeguard")]
    grp = sub.groupby(["System", "Model"], observed=True)
    total = grp.size()
    completed = grp["utility"].sum()
    resisted = total - grp["security"].sum()
    wide = pd.DataFrame({
        "Completed": completed.astype(int).astype(str) + "/" + total.astype(int).astype(str),
        "Resisted": resisted.astype(int).astype(str) + "/" + total.astype(int).astype(str),
    })
    return wide.sort_index()


def _latex(df: pd.DataFrame, caption: str, label: str) -> str:
    body = df.to_latex(multirow=True, escape=False, caption=caption, label=label,
                       column_format="ll" + "r" * df.shape[1])
    return "% Requires \\usepackage{booktabs,multirow}\n" + body


def utility_table(df: pd.DataFrame, suite: str) -> str:
    caption = (rf"Utility on the AgentDojo {suite} suite: user tasks completed correctly, safe "
               rf"(out of 21) and under each injection attack (out of 105).")
    return _latex(utility_frame(df, suite), caption, f"tab:agentdojo-{suite}-utility")


def security_table(df: pd.DataFrame, suite: str) -> str:
    caption = (rf"Security on the AgentDojo {suite} suite: task and injection pairs that resisted "
               rf"each attack (out of 105).")
    return _latex(security_frame(df, suite), caption, f"tab:agentdojo-{suite}-security")


def adversarial_table(df: pd.DataFrame, suite: str) -> str:
    caption = (rf"Adversarial evaluation on the AgentDojo {suite} suite: each subagent prompt is "
               rf"replaced by the injected command to model a compromised subagent.")
    return _latex(adversarial_frame(df, suite), caption, f"tab:agentdojo-{suite}-adversarial")


def _wilson(successes: int, trials: int) -> tuple[float, float]:
    ci = binomtest(successes, trials).proportion_ci(method="wilson")
    return ci.low, ci.high


# 95 percent CI for a paired proportion difference using Newcombe 1998 method 10.
def newcombe_paired_diff(pairs: list[tuple[bool, bool]]):
    n = len(pairs)
    a = sum(1 for x, y in pairs if x and y)
    b = sum(1 for x, y in pairs if x and not y)
    c = sum(1 for x, y in pairs if not x and y)
    d = n - a - b - c
    p1, p2 = (a + b) / n, (a + c) / n
    diff = p1 - p2
    l1, u1 = _wilson(a + b, n)
    l2, u2 = _wilson(a + c, n)
    prod = (a + b) * (c + d) * (a + c) * (b + d)
    if prod == 0:
        phi = 0.0
    else:
        cross = a * d - b * c
        cross = max(cross - n / 2, 0) if cross > 0 else cross
        phi = cross / math.sqrt(prod)
    lo = diff - math.sqrt(max((p1 - l1) ** 2 - 2 * phi * (p1 - l1) * (u2 - p2) + (u2 - p2) ** 2, 0))
    hi = diff + math.sqrt(max((u1 - p1) ** 2 - 2 * phi * (u1 - p1) * (p2 - l2) + (p2 - l2) ** 2, 0))
    return 100 * diff, 100 * lo, 100 * hi


def ci_table(df: pd.DataFrame, suites: list[str], models: dict[str, Model]) -> str:
    settings = [("No attack, no policies", BENIGN, "nopolicy"),
                ("No attack, with policies", BENIGN, "policy")] \
        + [(f"{ATTACK_LABELS[a]} attack", a, "policy") for a in ATTACKS]
    rows = []
    for suite in suites:
        for model in models.values():
            disp = display(model)
            for setting, attack, variant in settings:
                sub = df[(df["suite"] == suite) & (df["Model"] == disp)
                         & (df["variant"] == variant) & (df["attack"] == attack)]
                key = ["task", "injection", "rep"]
                tg = sub[sub["system"] == "typeguard"].set_index(key)["utility"]
                cm = sub[sub["system"] == "camel"].set_index(key)["utility"]
                common = tg.index.intersection(cm.index)
                if common.empty:
                    continue
                pairs = [(bool(tg[i]), bool(cm[i])) for i in common]
                _, lo, hi = newcombe_paired_diff(pairs)
                rows.append({"Suite": suite, "Model": disp, "Setting": setting,
                             r"95\% CI (pp)": f"$[{lo:+.1f}, {hi:+.1f}]$"})
    if not rows:
        return "% no paired data yet\n"
    caption = (r"95\% confidence intervals for the difference in task completion rates "
               r"(TypeGuard $-$ CaMeL), using Newcombe's score interval for paired proportions.")
    body = pd.DataFrame(rows).to_latex(index=False, escape=False, caption=caption,
                                       label="tab:agentdojo-cis", column_format="lllr")
    return "% Requires \\usepackage{booktabs}\n" + body


def process(logdir, models, suites) -> Path:
    df = load_frame(logdir, models)
    outdir = logdir / "results"
    outdir.mkdir(parents=True, exist_ok=True)
    if df.empty:
        print(f"No results under {logdir}")
        return outdir
    df.to_json(outdir / "dump.jsonl", orient="records", lines=True)
    for suite in suites:
        present = df[df["suite"] == suite]
        if present.empty:
            continue
        if present["attack"].isin(ATTACKS).any():
            (outdir / f"utility_{suite}.tex").write_text(utility_table(df, suite))
            (outdir / f"security_{suite}.tex").write_text(security_table(df, suite))
            print(f"\n{suite} utility:\n{utility_frame(df, suite).to_string()}")
            print(f"\n{suite} security:\n{security_frame(df, suite).to_string()}")
        if (present["attack"] == "adversarial").any():
            (outdir / f"adversarial_{suite}.tex").write_text(adversarial_table(df, suite))
            print(f"\n{suite} adversarial:\n{adversarial_frame(df, suite).to_string()}")
    (outdir / "confidence_intervals.tex").write_text(ci_table(df, suites, models))
    print(f"\nProcessed {len(df)} task evaluations into {outdir}")
    return outdir
