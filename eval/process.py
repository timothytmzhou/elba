"""Turn the result tree into dump.jsonl and the LaTeX tables under <logdir>/results."""

from __future__ import annotations

import argparse
from collections import Counter
import json
import math
from pathlib import Path

import pandas as pd
from scipy.stats import binomtest

from benchmark import BENIGN, Benchmark, pipeline_name
from config import Model, display, load_model

SYSTEM_LABELS = {
    ("elba", "policy"): "Elba",
    ("elba", "nopolicy"): "Elba (no policy)",
    ("camel", "policy"): "CaMeL",
    ("camel", "nopolicy"): "CaMeL (no policy)",
}
SYSTEM_ORDER = list(SYSTEM_LABELS.values())
ATTACK_LABELS = {"direct": "Direct", "important_instructions": r"Imp.\ Instr.",
                 "tool_knowledge": "Tool Instr."}
ATTACKS = list(ATTACK_LABELS)


# Keep unscored trials in the denominator
def load_frame(logdir: Path, models: dict[str, Model]) -> pd.DataFrame:
    rows = []
    # A single repetition is stored flat, without the rep1 directory.
    for rep_dir in sorted(logdir.glob("rep*")) or [logdir]:
        rep = int(rep_dir.name[3:]) if rep_dir.name.startswith("rep") else 1
        for model in models.values():
            for system, variant in SYSTEM_LABELS:
                stem = Benchmark(system, variant, model.name, rep, "", "")
                for path in sorted((rep_dir / pipeline_name(stem)).glob("*/*/*/*.json")):
                    result = json.loads(path.read_text())
                    for metric in ("utility", "security"):
                        if result.get(metric) is not None and type(result[metric]) is not bool:
                            raise ValueError(f"Invalid {metric} verdict in {path}")
                    rows.append({
                        "System": SYSTEM_LABELS[(system, variant)],
                        "Model": display(model),
                        "system": system, "variant": variant,
                        "suite": path.parts[-4], "task": path.parts[-3],
                        "attack": path.parts[-2], "injection": path.stem, "rep": rep,
                        "utility": None if result.get("utility") is None else int(result["utility"]),
                        "security": None if result.get("security") is None else int(result["security"]),
                    })
    df = pd.DataFrame(rows)
    if df.empty:
        return df
    for metric in ("utility", "security"):
        df[metric] = df[metric].astype("Int64")
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
    sub = df[(df["suite"] == suite) & df["attack"].isin(ATTACKS)].copy()
    sub["resisted"] = sub["security"].eq(0).fillna(False)
    grp = sub.groupby(["System", "Model", "attack"], observed=True)
    resisted = grp["resisted"].sum()
    return _grid(sub, resisted, ATTACKS)


def adversarial_frame(df: pd.DataFrame, suite: str) -> pd.DataFrame:
    sub = df[(df["suite"] == suite) & (df["attack"] == "adversarial") & (df["system"] == "elba")].copy()
    sub["resisted"] = sub["security"].eq(0).fillna(False)
    grp = sub.groupby(["System", "Model"], observed=True)
    total = grp.size()
    completed = grp["utility"].sum()
    resisted = grp["resisted"].sum()
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
    frame = adversarial_frame(df, suite)
    denominators = {cell.split("/")[1] for cell in frame.values.flat}
    suffix = f" (/{next(iter(denominators))})" if len(denominators) == 1 else ""
    caption = "Adversarial evaluation: injections resisted and tasks completed under attack (higher is better)."
    label = "tab:adversarial-security" if suite == "slack" else f"tab:adversarial-{suite}"
    lines = _table_start(caption, label, "llrr")
    lines += [f"System & Model & Injections resisted{suffix} & Tasks completed{suffix} " + r"\\",
              r"\midrule"]
    previous_system = None
    for (system, model), row in frame.iterrows():
        if previous_system is not None and system != previous_system:
            lines.append(r"\midrule")
        counts = [row["Resisted"], row["Completed"]]
        if suffix:
            counts = [cell.split("/")[0] for cell in counts]
        cells = [system if system != previous_system else "", model.replace("Gpt ", "GPT "), *counts]
        lines.append(" & ".join(cells) + r" \\")
        previous_system = system
    return _table_end(lines)


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


def _table_start(caption: str, label: str, columns: str) -> list[str]:
    return [r"\begin{table}[htbp]", r"\centering", r"\small",
            rf"\caption{{{caption}}}", rf"\label{{{label}}}",
            rf"\begin{{tabular}}{{{columns}}}", r"\toprule"]


def _table_end(lines: list[str]) -> str:
    return "\n".join(lines + [r"\bottomrule", r"\end{tabular}", r"\end{table}", ""])


def _model_label(model: Model) -> str:
    return display(model).replace("Gpt ", "GPT ")


def ci_table(df: pd.DataFrame, suites: list[str], models: dict[str, Model]) -> str:
    tables = []
    for suite in suites:
        if df[(df["suite"] == suite) & df["attack"].isin([BENIGN] + ATTACKS)].empty:
            continue
        caption = (r"95\% confidence intervals for the difference in task completion rates "
                   r"($\mathrm{Elba} - \text{CaMeL}$), in percentage points, computed using "
                   r"Newcombe's score interval for the difference in paired proportions.")
        label = "tab:agentdojo-cis" if len(suites) == 1 else f"tab:agentdojo-{suite}-cis"
        lines = _table_start(caption, label, "llrrrr")
        lines.insert(5, r"\setlength{\tabcolsep}{3pt}")
        lines += [r"Model & Policies & No attack & Direct & Important Instr. & Tool Instr. \\",
                  r"\midrule"]
        written = 0
        for variant in ("policy", "nopolicy"):
            if written:
                lines.append(r"\midrule")
            for model in models.values():
                cells = []
                for attack in [BENIGN] + ATTACKS:
                    sub = df[(df["suite"] == suite) & (df["Model"] == display(model))
                             & (df["variant"] == variant) & (df["attack"] == attack)]
                    key = ["task", "injection", "rep"]
                    tg = sub[sub["system"] == "elba"].set_index(key)["utility"]
                    cm = sub[sub["system"] == "camel"].set_index(key)["utility"]
                    if tg.empty or cm.empty:
                        cells.append("N/A")
                        continue
                    if (not tg.index.is_unique or not cm.index.is_unique
                            or set(tg.index) != set(cm.index)):
                        raise ValueError(f"Unmatched trials for {suite} {model.name} {variant} {attack}")
                    pairs = list(zip(tg.fillna(0).astype(bool), cm.reindex(tg.index).fillna(0).astype(bool)))
                    _, lo, hi = newcombe_paired_diff(pairs)
                    cells.append(f"$[{lo:+.1f}, {hi:+.1f}]$")
                if all(cell == "N/A" for cell in cells):
                    continue
                policy = "Yes" if variant == "policy" else "No"
                lines.append(" & ".join([_model_label(model), policy, *cells]) + r" \\")
                written += 1
        if written:
            tables.append(_table_end(lines))
    return "\n".join(tables)


def bootstrap_rate_interval(successes: list[int], trials_per_run: int) -> tuple[float, float]:
    """Exact percentile bootstrap over complete benchmark runs"""
    if len(successes) < 2 or trials_per_run <= 0:
        raise ValueError("At least two nonempty benchmark runs are required")
    if any(not 0 <= count <= trials_per_run for count in successes):
        raise ValueError("Success counts must be between zero and the trial count")
    distribution = Counter({0: 1})
    for _ in successes:
        following = Counter()
        for total, count in distribution.items():
            for value in successes:
                following[total + value] += count
        distribution = following
    population = sum(distribution.values())

    def order_statistic(index):
        cumulative = 0
        for total, count in sorted(distribution.items()):
            cumulative += count
            if cumulative > index:
                return 100 * total / (len(successes) * trials_per_run)
        raise ValueError("Invalid bootstrap quantile")

    def percentile(q):
        position = (population - 1) * q
        fraction = position - math.floor(position)
        return (order_statistic(math.floor(position)) * (1 - fraction)
                + order_statistic(math.ceil(position)) * fraction)

    return percentile(0.025), percentile(0.975)


def adversarial_ci_table(df: pd.DataFrame, suites: list[str], models: dict[str, Model]) -> str:
    tables = []
    for suite in suites:
        sub = df[(df["suite"] == suite) & (df["attack"] == "adversarial") & (df["system"] == "elba")]
        if sub.empty:
            continue
        caption = r"Task completion rates and 95\% confidence intervals for the adversarial evaluation."
        label = "tab:adversarial-utility-cis" if len(suites) == 1 else f"tab:adversarial-{suite}-cis"
        lines = _table_start(caption, label, "llrcrc")
        lines += [r"\multirow{2}{*}{Model} & \multirow{2}{*}{Policies} & \multicolumn{2}{c}{Tasks completed (\%)} & \multicolumn{2}{c}{Injections resisted (\%)} \\",
                  r"\cmidrule(lr){3-4}\cmidrule(lr){5-6}",
                  r" & & Rate & 95\% CI & Rate & 95\% CI \\", r"\midrule"]
        written = 0
        for variant in ("policy", "nopolicy"):
            if written:
                lines.append(r"\midrule")
            for model in models.values():
                records = sub[(sub["Model"] == display(model)) & (sub["variant"] == variant)]
                if records.empty:
                    continue
                groups = [group for _, group in records.groupby("rep", sort=True)]
                keys = [set(zip(group["task"], group["injection"])) for group in groups]
                if any(len(group) != len(key) or key != keys[0] for group, key in zip(groups, keys)):
                    raise ValueError(f"Benchmark runs contain different trials for {model.name} {variant}")
                completed = [int(group["utility"].eq(1).sum()) for group in groups]
                resisted = [int(group["security"].eq(0).sum()) for group in groups]

                def interval(counts):
                    if len(groups) < 2:
                        return "N/A"
                    lo, hi = bootstrap_rate_interval(counts, len(groups[0]))
                    return f"[{lo:.1f}, {hi:.1f}]"

                cells = [_model_label(model), "Yes" if variant == "policy" else "No",
                         f"{100 * sum(completed) / len(records):.1f}", interval(completed),
                         f"{100 * sum(resisted) / len(records):.1f}",
                         interval(resisted) if variant == "nopolicy" else "N/A"]
                lines.append(" & ".join(cells) + r" \\")
                written += 1
        tables.append(_table_end(lines))
    return "\n".join(tables)


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
    intervals = ci_table(df, suites, models) + adversarial_ci_table(df, suites, models)
    (outdir / "confidence_intervals.tex").write_text(intervals)
    print(f"\nProcessed {len(df)} task evaluations into {outdir}")
    return outdir


def main() -> None:
    directory = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Reproduce tables from saved results without model calls")
    parser.add_argument("logdirs", nargs="*", type=Path,
                        default=[directory / "data/main", directory / "data/adversarial"])
    parser.add_argument("--models", nargs="+", type=Path,
                        default=[directory / "configs" / f"{name}.json" for name in
                                 ("opus-4.7-high", "opus-4.8-high", "gpt-5.4-high", "sonnet-5-high")])
    parser.add_argument("--suites", nargs="+", default=["slack"])
    args = parser.parse_args()
    models = {model.name: model for model in map(load_model, args.models)}
    for logdir in args.logdirs:
        process(logdir, models, args.suites)


if __name__ == "__main__":
    main()
