"""Data processing: raw dump + LaTeX tables from per-task result files.

Strictly separate from execution (execute.py): this module only reads the
result tree an earlier run produced. Outputs, under <logdir>/results/:

  dump.jsonl               one record per task evaluation with everything
                           tracked: identity, utility/security verdicts,
                           duration, token usage, the agent's final output
                           and full message log, error, transcript path.
  table_<suite>.tex        the paper table for one suite, in the format of
                           Garby et al. (arXiv:2602.20064) Table 1: rows are
                           system x model; utility cells "n/N (p% +- hw)"
                           with a clustered Student-t 95% CI over sampling
                           units, security cells "n/N [lo, hi]" with a 95%
                           Wilson score interval.
  confidence_intervals.tex TypeGuard - CaMeL paired difference per setting
                           (Newcombe's score interval), i.e. the preprint's
                           Table 3.
  summary.txt              plain-text rendering of the same numbers.

Usage (standalone; run.py invokes this automatically after a run):
    python eval/process.py --logdir logs/eval --models eval/configs/*.json
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from statistics import NormalDist

from experiment import ATTACKS, BENIGN, Model, SUITES, suite_tasks

Z975 = NormalDist().inv_cdf(0.975)

SYSTEM_LABELS = {
    ("typeguard", "policy"): r"TypeGuard",
    ("typeguard", "nopolicy"): r"TypeGuard (no policy)",
    ("camel", "policy"): r"CaMeL",
    ("camel", "nopolicy"): r"CaMeL (no policy)",
}
ROW_ORDER = list(SYSTEM_LABELS)
ATTACK_LABELS = {"direct": "Direct", "important_instructions": r"Imp.\ Instr."}


# ---------------------------------------------------------------------------
# Statistics


def t_quantile_975(df: int) -> float:
    """Student-t 0.975 quantile via the Cornish-Fisher expansion (accurate to
    ~1e-3 for df >= 5; exact enough for a CI half-width printed to 0.1)."""
    if df <= 0:
        return float("nan")
    z = Z975
    return (z + (z**3 + z) / (4 * df)
            + (5 * z**5 + 16 * z**3 + 3 * z) / (96 * df**2)
            + (3 * z**7 + 19 * z**5 + 17 * z**3 - 15 * z) / (384 * df**3))


def clustered_utility_ci(unit_outcomes: list[list[bool]]) -> tuple[int, int, float, float]:
    """(successes, trials, mean %, CI half-width in points).

    The sampling unit is the task (safe) or task/injection pair (attacked);
    each unit is averaged over its k repetitions and the Student-t CI is
    taken over units — the clustered estimator of Garby et al., Table 1.
    """
    n_units = len(unit_outcomes)
    successes = sum(sum(reps) for reps in unit_outcomes)
    trials = sum(len(reps) for reps in unit_outcomes)
    means = [sum(reps) / len(reps) for reps in unit_outcomes]
    mean = sum(means) / n_units
    if n_units < 2:
        return successes, trials, 100 * mean, float("nan")
    var = sum((m - mean) ** 2 for m in means) / (n_units - 1)
    hw = t_quantile_975(n_units - 1) * math.sqrt(var / n_units) * 100
    return successes, trials, 100 * mean, hw


def wilson_interval(successes: int, trials: int) -> tuple[float, float]:
    """95% Wilson score interval, in percent."""
    if trials == 0:
        return float("nan"), float("nan")
    z2 = Z975**2
    p = successes / trials
    denom = 1 + z2 / trials
    center = (p + z2 / (2 * trials)) / denom
    half = Z975 * math.sqrt(p * (1 - p) / trials + z2 / (4 * trials**2)) / denom
    return 100 * max(center - half, 0), 100 * min(center + half, 1)


def newcombe_paired_diff(pairs: list[tuple[bool, bool]]) -> tuple[float, float, float]:
    """95% CI for a difference in paired proportions p1 - p2 (percentage
    points), by Newcombe's score-interval method (Newcombe 1998, method 10).

    `pairs` holds (outcome_system1, outcome_system2) per sampling unit.
    """
    n = len(pairs)
    a = sum(1 for x, y in pairs if x and y)
    b = sum(1 for x, y in pairs if x and not y)
    c = sum(1 for x, y in pairs if not x and y)
    d = n - a - b - c
    p1, p2 = (a + b) / n, (a + c) / n
    diff = p1 - p2
    l1, u1 = (x / 100 for x in wilson_interval(a + b, n))
    l2, u2 = (x / 100 for x in wilson_interval(a + c, n))
    prod = (a + b) * (c + d) * (a + c) * (b + d)
    if prod == 0:
        phi = 0.0
    else:
        cross = a * d - b * c
        # continuity correction on positive association, per Newcombe (1998)
        cross = max(cross - n / 2, 0) if cross > 0 else cross
        phi = cross / math.sqrt(prod)
    lo = diff - math.sqrt(max((p1 - l1) ** 2 - 2 * phi * (p1 - l1) * (u2 - p2) + (u2 - p2) ** 2, 0))
    hi = diff + math.sqrt(max((u1 - p1) ** 2 - 2 * phi * (u1 - p1) * (p2 - l2) + (p2 - l2) ** 2, 0))
    return 100 * diff, 100 * lo, 100 * hi


# ---------------------------------------------------------------------------
# Loading results


def load_results(logdir: Path, models: dict[str, Model]) -> list[dict]:
    """Flatten every finished result file into dump records."""
    records = []
    for rep_dir in sorted(logdir.glob("rep*")):
        rep = int(rep_dir.name[3:])
        for model in models.values():
            for (system, variant), _ in SYSTEM_LABELS.items():
                pipeline = model.pipeline_name(system, variant)
                for path in sorted((rep_dir / pipeline).glob("*/*/*/*.json")):
                    try:
                        r = json.loads(path.read_text())
                    except (OSError, json.JSONDecodeError):
                        continue
                    if r.get("utility") not in (True, False):
                        continue
                    suite, task, attack = path.parts[-4], path.parts[-3], path.parts[-2]
                    messages = r.get("messages") or []
                    final = next(
                        (blk.get("content") or blk.get("text", "")
                         for m in reversed(messages) if m.get("role") == "assistant"
                         for blk in (m.get("content") or [])
                         if isinstance(blk, dict)),
                        None)
                    records.append({
                        "rep": rep, "system": system, "variant": variant,
                        "model": model.name, "pipeline": pipeline,
                        "suite": suite, "task": task, "attack": attack,
                        "injection_task": path.stem,
                        "utility": r["utility"], "security": r["security"],
                        "duration_s": r.get("duration"),
                        "tokens": r.get("tokens"),
                        "error": r.get("error"),
                        "final_output": final,
                        "messages": messages,
                        "agent_transcript": r.get("agent_transcript"),
                        "result_file": str(path),
                    })
    return records


def _by(records, **filters):
    return [r for r in records
            if all(r[k] == v for k, v in filters.items())]


def _units(records: list[dict], key) -> list[list[bool]]:
    """Group per-rep outcomes by sampling unit; key maps record -> unit id."""
    units: dict = {}
    for r in records:
        units.setdefault(key(r), []).append(r)
    return [[x["utility"] for x in sorted(v, key=lambda x: x["rep"])]
            for _, v in sorted(units.items())]


# ---------------------------------------------------------------------------
# Cells and tables


def utility_cell(records: list[dict], key) -> str:
    if not records:
        return "--"
    n, total, pct, hw = clustered_utility_ci(_units(records, key))
    hw_s = "" if math.isnan(hw) else rf" $\pm$ {hw:.1f}"
    return rf"{n}/{total} ({pct:.1f}\%{hw_s})"


def security_cell(records: list[dict]) -> str:
    if not records:
        return "--"
    resisted = sum(1 for r in records if not r["security"])  # security=True means the attack succeeded
    lo, hi = wilson_interval(resisted, len(records))
    return rf"{resisted}/{len(records)} [{lo:.1f}, {hi:.1f}]"


def suite_table(records: list[dict], suite: str, models: dict[str, Model],
                attacks: list[str], repeats: int) -> str:
    user_tasks, injection_tasks = suite_tasks(suite)
    n_pairs = len(user_tasks) * len(injection_tasks)
    ncols = 2 + 1 + 2 * len(attacks)

    util_group = [r"\multicolumn{%d}{c}{Utility\textsuperscript{\dag}}" % (1 + len(attacks))]
    sec_group = [r"\multicolumn{%d}{c}{Security\textsuperscript{\ddag}}" % len(attacks)]
    sub = ["Safe"] + [f"Attacked ({ATTACK_LABELS[a]})" for a in attacks] \
        + [f"{ATTACK_LABELS[a]} ({repeats * n_pairs})" for a in attacks]

    lines = [
        r"% Requires: \usepackage{booktabs,multirow}",
        r"\begin{table}",
        r"\centering\small",
        rf"\caption{{Utility\textsuperscript{{\dag}} and security\textsuperscript{{\ddag}} on the "
        rf"AgentDojo {suite} suite ({len(user_tasks)} user tasks $\times$ "
        rf"{len(injection_tasks)} injection attacks, $k = {repeats}$ repetitions).}}",
        rf"\label{{tab:agentdojo-{suite}}}",
        r"\begin{tabular}{l l " + "l" * (ncols - 2) + "}",
        r"\toprule",
        " & & " + " & ".join(util_group + sec_group) + r" \\",
        rf"\cmidrule(lr){{3-{3 + len(attacks)}}} \cmidrule(lr){{{4 + len(attacks)}-{ncols}}}",
        "System & Model & " + " & ".join(sub) + r" \\",
        r"\midrule",
    ]

    for system, variant in ROW_ORDER:
        group_rows = []
        for model in models.values():
            recs = _by(records, system=system, variant=variant,
                       model=model.name, suite=suite)
            if not recs:
                continue
            cells = [utility_cell(_by(recs, attack=BENIGN), key=lambda r: r["task"])]
            for attack in attacks:
                cells.append(utility_cell(
                    _by(recs, attack=attack),
                    key=lambda r: (r["task"], r["injection_task"])))
            for attack in attacks:
                cells.append(security_cell(_by(recs, attack=attack)))
            group_rows.append((model.display, cells))
        if not group_rows:
            continue
        label = SYSTEM_LABELS[(system, variant)]
        for i, (model_disp, cells) in enumerate(group_rows):
            if i > 0:
                head = ""
            elif len(group_rows) > 1:
                head = rf"\multirow{{{len(group_rows)}}}{{*}}{{{label}}}"
            else:
                head = label
            lines.append(f"{head} & {model_disp} & " + " & ".join(cells) + r" \\")
        lines.append(r"\addlinespace")

    denom = " & & " + " & ".join(
        [rf"({repeats * len(user_tasks)} = {repeats} $\times$ {len(user_tasks)})"]
        + [rf"({repeats * n_pairs} = {repeats} $\times$ {n_pairs})"] * len(attacks)
        + [""] * len(attacks)) + r" \\"
    lines += [
        denom,
        r"\bottomrule",
        r"\end{tabular}",
        r"\begin{minipage}{\linewidth}\smallskip\footnotesize",
        r"\textsuperscript{\dag} Utility: user tasks completed correctly; Safe and Attacked denote "
        r"utility without/with (resp.)\ injected attacks. Parentheses give the mean with a 95\% "
        r"confidence interval (Student-$t$), taking the user task (Safe) or task/injection pair "
        r"(Attacked) as the sampling unit, each averaged over its $k$ repetitions.\\",
        r"\textsuperscript{\ddag} Security: user-task/injection pairs successfully rebutting the "
        r"attack, per injection attack. Brackets give a 95\% Wilson score interval at the pair "
        r"level.",
        r"\end{minipage}",
        r"\end{table}",
    ]
    return "\n".join(lines) + "\n"


def ci_table(records: list[dict], suites: list[str], models: dict[str, Model],
             attacks: list[str]) -> str:
    """TypeGuard - CaMeL paired-difference CIs (the preprint's Table 3)."""
    settings = [("No attack, no policies", BENIGN, "nopolicy"),
                ("No attack, with policies", BENIGN, "policy")] + [
        (f"{ATTACK_LABELS[a]} attack", a, "policy") for a in attacks]
    lines = [
        r"\begin{table}",
        r"\centering\small",
        r"\caption{95\% confidence intervals for the difference in task-completion rates "
        r"(TypeGuard $-$ CaMeL), computed using Newcombe's score interval for the difference "
        r"in paired proportions.}",
        r"\label{tab:agentdojo-cis}",
        r"\begin{tabular}{lllr}",
        r"\toprule",
        r"Suite & Model & Setting & 95\% CI (pp) \\",
        r"\midrule",
    ]
    any_rows = False
    for suite in suites:
        for model in models.values():
            for setting, attack, variant in settings:
                tg = _by(records, system="typeguard", variant=variant,
                         model=model.name, suite=suite, attack=attack)
                cm = _by(records, system="camel", variant=variant,
                         model=model.name, suite=suite, attack=attack)
                tg_by_unit = {(r["task"], r["injection_task"], r["rep"]): r["utility"] for r in tg}
                cm_by_unit = {(r["task"], r["injection_task"], r["rep"]): r["utility"] for r in cm}
                common = sorted(set(tg_by_unit) & set(cm_by_unit))
                if not common:
                    continue
                pairs = [(tg_by_unit[u], cm_by_unit[u]) for u in common]
                _, lo, hi = newcombe_paired_diff(pairs)
                lines.append(rf"{suite} & {model.display} & {setting} & "
                             rf"$[{lo:+.1f}, {hi:+.1f}]$ \\")
                any_rows = True
    lines += [r"\bottomrule", r"\end{tabular}", r"\end{table}"]
    return ("\n".join(lines) + "\n") if any_rows else "% no paired data yet\n"


def summary_text(records: list[dict], suites: list[str], models: dict[str, Model],
                 attacks: list[str]) -> str:
    out = []
    for suite in suites:
        rows = []
        for system, variant in ROW_ORDER:
            for model in models.values():
                recs = _by(records, system=system, variant=variant,
                           model=model.name, suite=suite)
                if not recs:
                    continue
                cells = [utility_cell(_by(recs, attack=BENIGN), key=lambda r: r["task"])]
                for attack in attacks:
                    cells.append(utility_cell(_by(recs, attack=attack),
                                              key=lambda r: (r["task"], r["injection_task"])))
                for attack in attacks:
                    cells.append(security_cell(_by(recs, attack=attack)))
                label = f"{SYSTEM_LABELS[(system, variant)]} / {model.display}"
                rows.append((label, [c.replace("\\%", "%").replace("$\\pm$", "±") for c in cells]))
        if rows:
            out.append(f"== {suite} ==")
            head = ["safe"] + [f"util({a})" for a in attacks] + [f"sec({a})" for a in attacks]
            out.append(f"{'':38}" + "".join(f"{h:<26}" for h in head))
            for label, cells in rows:
                out.append(f"{label:<38}" + "".join(f"{c:<26}" for c in cells))
            out.append("")
    return "\n".join(out) + "\n"


# ---------------------------------------------------------------------------
# Entry point


def process(logdir: Path, models: dict[str, Model], suites: list[str],
            attacks: list[str], repeats: int) -> Path:
    records = load_results(logdir, models)
    outdir = logdir / "results"
    outdir.mkdir(parents=True, exist_ok=True)

    with (outdir / "dump.jsonl").open("w") as f:
        for r in records:
            f.write(json.dumps(r) + "\n")

    for suite in suites:
        if any(r["suite"] == suite for r in records):
            (outdir / f"table_{suite}.tex").write_text(
                suite_table(records, suite, models, attacks, repeats))
    (outdir / "confidence_intervals.tex").write_text(
        ci_table(records, suites, models, attacks))
    summary = summary_text(records, suites, models, attacks)
    (outdir / "summary.txt").write_text(summary)

    print(f"\n{summary}")
    print(f"Processed {len(records)} task evaluations into {outdir}:")
    for p in sorted(outdir.iterdir()):
        print(f"  {p}")
    return outdir


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--logdir", required=True)
    ap.add_argument("--models", nargs="+", required=True)
    ap.add_argument("--suites", default=",".join(SUITES))
    ap.add_argument("--attacks", default=",".join(ATTACKS))
    ap.add_argument("--repeats", type=int, default=1)
    args = ap.parse_args()
    models = {m.name: m for m in map(Model.load, args.models)}
    process(Path(args.logdir), models, args.suites.split(","),
            [a for a in args.attacks.split(",") if a], args.repeats)
    return 0


if __name__ == "__main__":
    main()
