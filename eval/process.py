"""Turn the result tree into the raw dump and the LaTeX tables.

Reads only what the runner wrote. Writes under <logdir>/results/.

    dump.jsonl                everything tracked per task evaluation
    table_<suite>.tex         the paper table for one suite
    confidence_intervals.tex  TypeGuard minus CaMeL paired difference CIs
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
    ("typeguard", "policy"): "TypeGuard",
    ("typeguard", "nopolicy"): "TypeGuard (no policy)",
    ("camel", "policy"): "CaMeL",
    ("camel", "nopolicy"): "CaMeL (no policy)",
}
ROW_ORDER = list(SYSTEM_LABELS)
ATTACK_LABELS = {"direct": "Direct", "important_instructions": r"Imp.\ Instr."}


def t_quantile_975(df: int) -> float:
    # Cornish Fisher expansion, accurate to about 1e-3 for df at least 5.
    if df <= 0:
        return float("nan")
    z = Z975
    return (z + (z**3 + z) / (4 * df)
            + (5 * z**5 + 16 * z**3 + 3 * z) / (96 * df**2)
            + (3 * z**7 + 19 * z**5 + 17 * z**3 - 15 * z) / (384 * df**3))


def clustered_utility_ci(unit_outcomes: list[list[bool]]):
    """Returns successes, trials, mean percent, and CI half width in points.

    Each unit is averaged over its repetitions and the Student t interval is
    taken over units. This is the clustered estimator of the reference paper.
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


def wilson_interval(successes: int, trials: int):
    if trials == 0:
        return float("nan"), float("nan")
    z2 = Z975**2
    p = successes / trials
    denom = 1 + z2 / trials
    center = (p + z2 / (2 * trials)) / denom
    half = Z975 * math.sqrt(p * (1 - p) / trials + z2 / (4 * trials**2)) / denom
    return 100 * max(center - half, 0), 100 * min(center + half, 1)


def newcombe_paired_diff(pairs: list[tuple[bool, bool]]):
    """95 percent CI for a paired proportion difference in points.

    Newcombe 1998 method 10.
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
        cross = max(cross - n / 2, 0) if cross > 0 else cross
        phi = cross / math.sqrt(prod)
    lo = diff - math.sqrt(max((p1 - l1) ** 2 - 2 * phi * (p1 - l1) * (u2 - p2) + (u2 - p2) ** 2, 0))
    hi = diff + math.sqrt(max((u1 - p1) ** 2 - 2 * phi * (u1 - p1) * (p2 - l2) + (p2 - l2) ** 2, 0))
    return 100 * diff, 100 * lo, 100 * hi


def load_results(logdir: Path, models: dict[str, Model]) -> list[dict]:
    records = []
    for rep_dir in sorted(logdir.glob("rep*")):
        rep = int(rep_dir.name[3:])
        for model in models.values():
            for system, variant in SYSTEM_LABELS:
                pipeline = model.pipeline_name(system, variant)
                for path in sorted((rep_dir / pipeline).glob("*/*/*/*.json")):
                    try:
                        r = json.loads(path.read_text())
                    except (OSError, json.JSONDecodeError):
                        continue
                    if r.get("utility") not in (True, False):
                        continue
                    final = next((blk.get("content") or blk.get("text", "")
                                  for m in reversed(r.get("messages") or [])
                                  if m.get("role") == "assistant"
                                  for blk in (m.get("content") or []) if isinstance(blk, dict)), None)
                    records.append({
                        "rep": rep, "system": system, "variant": variant, "model": model.name,
                        "pipeline": pipeline, "suite": path.parts[-4], "task": path.parts[-3],
                        "attack": path.parts[-2], "injection_task": path.stem,
                        "utility": r["utility"], "security": r["security"],
                        "duration_s": r.get("duration"), "tokens": r.get("tokens"),
                        "timestamp": r.get("evaluation_timestamp"),
                        "error": r.get("error"), "final_output": final,
                        "messages": r.get("messages") or [],
                        "agent_transcript": r.get("agent_transcript"), "result_file": str(path),
                    })
    return records


def _by(records, **filters):
    return [r for r in records if all(r[k] == v for k, v in filters.items())]


def _units(records, key) -> list[list[bool]]:
    units: dict = {}
    for r in records:
        units.setdefault(key(r), []).append(r)
    return [[x["utility"] for x in sorted(v, key=lambda x: x["rep"])] for _, v in sorted(units.items())]


def utility_cell(records, key) -> str:
    if not records:
        return "--"
    n, total, pct, hw = clustered_utility_ci(_units(records, key))
    hw_s = "" if math.isnan(hw) else rf" $\pm$ {hw:.1f}"
    return rf"{n}/{total} ({pct:.1f}\%{hw_s})"


def security_cell(records) -> str:
    if not records:
        return "--"
    resisted = sum(1 for r in records if not r["security"])  # security True means the attack won
    lo, hi = wilson_interval(resisted, len(records))
    return rf"{resisted}/{len(records)} [{lo:.1f}, {hi:.1f}]"


def row_cells(records, system, variant, model, suite, attacks) -> list[str] | None:
    recs = _by(records, system=system, variant=variant, model=model.name, suite=suite)
    if not recs:
        return None
    cells = [utility_cell(_by(recs, attack=BENIGN), lambda r: r["task"])]
    cells += [utility_cell(_by(recs, attack=a), lambda r: (r["task"], r["injection_task"]))
              for a in attacks]
    cells += [security_cell(_by(recs, attack=a)) for a in attacks]
    return cells


FOOTNOTES = [
    r"\begin{minipage}{\linewidth}\smallskip\footnotesize",
    r"\textsuperscript{\dag} Utility. User tasks completed correctly. Safe and Attacked denote "
    r"utility without and with injected attacks. Parentheses give the mean with a 95\% "
    r"confidence interval (Student $t$), taking the user task (Safe) or task and injection pair "
    r"(Attacked) as the sampling unit, each averaged over its $k$ repetitions.\\",
    r"\textsuperscript{\ddag} Security. Task and injection pairs that resisted the attack, per "
    r"injection attack. Brackets give a 95\% Wilson score interval at the pair level.",
    r"\end{minipage}",
]


def suite_table(records, suite, models, attacks, repeats) -> str:
    user_tasks, injection_tasks = suite_tasks(suite)
    n_pairs = len(user_tasks) * len(injection_tasks)
    ncols = 3 + 2 * len(attacks)
    util_hdr = r"\multicolumn{%d}{c}{Utility\textsuperscript{\dag}}" % (1 + len(attacks))
    sec_hdr = r"\multicolumn{%d}{c}{Security\textsuperscript{\ddag}}" % len(attacks)
    sub = ["Safe"] + [f"Attacked ({ATTACK_LABELS[a]})" for a in attacks] \
        + [f"{ATTACK_LABELS[a]} ({repeats * n_pairs})" for a in attacks]

    lines = [
        r"% Requires \usepackage{booktabs,multirow}",
        r"\begin{table}", r"\centering\small",
        rf"\caption{{Utility\textsuperscript{{\dag}} and security\textsuperscript{{\ddag}} on the "
        rf"AgentDojo {suite} suite ({len(user_tasks)} user tasks $\times$ {len(injection_tasks)} "
        rf"injection attacks, $k = {repeats}$ repetitions).}}",
        rf"\label{{tab:agentdojo-{suite}}}",
        r"\begin{tabular}{l l " + "l" * (ncols - 2) + "}", r"\toprule",
        " & & " + " & ".join([util_hdr, sec_hdr]) + r" \\",
        rf"\cmidrule(lr){{3-{3 + len(attacks)}}} \cmidrule(lr){{{4 + len(attacks)}-{ncols}}}",
        "System & Model & " + " & ".join(sub) + r" \\", r"\midrule",
    ]
    for system, variant in ROW_ORDER:
        group = [(m.display, row_cells(records, system, variant, m, suite, attacks))
                 for m in models.values()]
        group = [(d, c) for d, c in group if c]
        if not group:
            continue
        label = SYSTEM_LABELS[(system, variant)]
        for i, (disp, cells) in enumerate(group):
            head = "" if i else (rf"\multirow{{{len(group)}}}{{*}}{{{label}}}" if len(group) > 1 else label)
            lines.append(f"{head} & {disp} & " + " & ".join(cells) + r" \\")
        lines.append(r"\addlinespace")
    denom = " & & " + " & ".join(
        [rf"({repeats * len(user_tasks)} = {repeats} $\times$ {len(user_tasks)})"]
        + [rf"({repeats * n_pairs} = {repeats} $\times$ {n_pairs})"] * len(attacks)
        + [""] * len(attacks)) + r" \\"
    lines += [denom, r"\bottomrule", r"\end{tabular}", *FOOTNOTES, r"\end{table}"]
    return "\n".join(lines) + "\n"


def ci_table(records, suites, models, attacks) -> str:
    settings = [("No attack, no policies", BENIGN, "nopolicy"),
                ("No attack, with policies", BENIGN, "policy")] \
        + [(f"{ATTACK_LABELS[a]} attack", a, "policy") for a in attacks]
    lines = [
        r"\begin{table}", r"\centering\small",
        r"\caption{95\% confidence intervals for the difference in task completion rates "
        r"(TypeGuard $-$ CaMeL), using Newcombe's score interval for paired proportions.}",
        r"\label{tab:agentdojo-cis}", r"\begin{tabular}{lllr}", r"\toprule",
        r"Suite & Model & Setting & 95\% CI (pp) \\", r"\midrule",
    ]
    rows = 0
    for suite in suites:
        for model in models.values():
            for setting, attack, variant in settings:
                key = lambda r: (r["task"], r["injection_task"], r["rep"])
                tg = {key(r): r["utility"] for r in _by(records, system="typeguard",
                      variant=variant, model=model.name, suite=suite, attack=attack)}
                cm = {key(r): r["utility"] for r in _by(records, system="camel",
                      variant=variant, model=model.name, suite=suite, attack=attack)}
                common = sorted(set(tg) & set(cm))
                if not common:
                    continue
                _, lo, hi = newcombe_paired_diff([(tg[u], cm[u]) for u in common])
                lines.append(rf"{suite} & {model.display} & {setting} & $[{lo:+.1f}, {hi:+.1f}]$ \\")
                rows += 1
    lines += [r"\bottomrule", r"\end{tabular}", r"\end{table}"]
    return ("\n".join(lines) + "\n") if rows else "% no paired data yet\n"


def process(logdir, models, suites, attacks, repeats) -> Path:
    records = load_results(logdir, models)
    outdir = logdir / "results"
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "dump.jsonl").write_text("".join(json.dumps(r) + "\n" for r in records))
    for suite in suites:
        if any(r["suite"] == suite for r in records):
            (outdir / f"table_{suite}.tex").write_text(suite_table(records, suite, models, attacks, repeats))
            print(f"\n{suite}:")
            for system, variant in ROW_ORDER:
                for model in models.values():
                    cells = row_cells(records, system, variant, model, suite, attacks)
                    if cells:
                        row = (c.replace(r"\%", "%").replace(r"$\pm$", "±") for c in cells)
                        print(f"  {SYSTEM_LABELS[system, variant] + '/' + model.display:<36}"
                              + "".join(f"{c:<26}" for c in row))
    (outdir / "confidence_intervals.tex").write_text(ci_table(records, suites, models, attacks))
    print(f"\nProcessed {len(records)} task evaluations into {outdir}")
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
