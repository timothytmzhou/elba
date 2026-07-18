"""Turn the result tree into dump.jsonl and the LaTeX tables under <logdir>/results."""

from __future__ import annotations

import json
import math
from dataclasses import asdict
from pathlib import Path

from scipy.stats import binomtest

from benchmark import BENIGN, Benchmark, pipeline_name, suite_tasks
from config import Model, display
from result import Result, load_result

SYSTEM_LABELS = {
    ("typeguard", "policy"): "TypeGuard",
    ("typeguard", "nopolicy"): "TypeGuard (no policy)",
    ("camel", "policy"): "CaMeL",
    ("camel", "nopolicy"): "CaMeL (no policy)",
}
ROW_ORDER = list(SYSTEM_LABELS)
ATTACK_LABELS = {"direct": "Direct", "important_instructions": r"Imp.\ Instr."}


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


def load_results(logdir: Path, models: dict[str, Model]) -> list[tuple[Benchmark, Result]]:
    records = []
    for rep_dir in sorted(logdir.glob("rep*")):
        rep = int(rep_dir.name[3:])
        for model in models.values():
            for system, variant in SYSTEM_LABELS:
                stem = Benchmark(system, variant, model.name, rep, "", "")
                for path in sorted((rep_dir / pipeline_name(stem)).glob("*/*/*/*.json")):
                    bench = Benchmark(system, variant, model.name, rep, path.parts[-4],
                                      path.parts[-3], path.parts[-2], path.stem)
                    if result := load_result(path):
                        records.append((bench, result))
    return records


def _by(records, **filters):
    return [(b, r) for b, r in records
            if all(getattr(b, k) == v for k, v in filters.items())]


def utility_cell(records) -> str:
    if not records:
        return "--"
    n = sum(1 for _, r in records if r.utility)
    return rf"{n}/{len(records)} ({100 * n / len(records):.1f}\%)"


def security_cell(records) -> str:
    if not records:
        return "--"
    resisted = sum(1 for _, r in records if not r.security)  # security True means the attack won
    return rf"{resisted}/{len(records)}"


def row_cells(records, system, variant, model, suite, attacks) -> list[str] | None:
    recs = _by(records, system=system, variant=variant, model=model.name, suite=suite)
    if not recs:
        return None
    cells = [utility_cell(_by(recs, attack=BENIGN))]
    cells += [utility_cell(_by(recs, attack=a)) for a in attacks]
    cells += [security_cell(_by(recs, attack=a)) for a in attacks]
    return cells


FOOTNOTES = [
    r"\begin{minipage}{\linewidth}\smallskip\footnotesize",
    r"\textsuperscript{\dag} Utility. User tasks completed correctly, without (Safe) and with "
    r"(Attacked) injected attacks.\\",
    r"\textsuperscript{\ddag} Security. Task and injection pairs that resisted the attack, per "
    r"injection attack. Paired confidence intervals are reported in the appendix.",
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
        group = [(display(m), row_cells(records, system, variant, m, suite, attacks))
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
                key = lambda b: (b.task_id, b.injection_task_id, b.rep)
                tg = {key(b): r.utility for b, r in _by(records, system="typeguard",
                      variant=variant, model=model.name, suite=suite, attack=attack)}
                cm = {key(b): r.utility for b, r in _by(records, system="camel",
                      variant=variant, model=model.name, suite=suite, attack=attack)}
                common = sorted(set(tg) & set(cm))
                if not common:
                    continue
                _, lo, hi = newcombe_paired_diff([(tg[u], cm[u]) for u in common])
                lines.append(rf"{suite} & {display(model)} & {setting} & $[{lo:+.1f}, {hi:+.1f}]$ \\")
                rows += 1
    lines += [r"\bottomrule", r"\end{tabular}", r"\end{table}"]
    return ("\n".join(lines) + "\n") if rows else "% no paired data yet\n"


def process(logdir, models, suites, attacks, repeats) -> Path:
    records = load_results(logdir, models)
    outdir = logdir / "results"
    outdir.mkdir(parents=True, exist_ok=True)
    (outdir / "dump.jsonl").write_text("".join(
        json.dumps({"benchmark": asdict(b), "result": asdict(r)}) + "\n" for b, r in records))
    for suite in suites:
        if any(b.suite == suite for b, _ in records):
            (outdir / f"table_{suite}.tex").write_text(suite_table(records, suite, models, attacks, repeats))
            print(f"\n{suite}:")
            for system, variant in ROW_ORDER:
                for model in models.values():
                    cells = row_cells(records, system, variant, model, suite, attacks)
                    if cells:
                        row = (c.replace(r"\%", "%") for c in cells)
                        print(f"  {SYSTEM_LABELS[system, variant] + '/' + display(model):<36}"
                              + "".join(f"{c:<26}" for c in row))
    (outdir / "confidence_intervals.tex").write_text(ci_table(records, suites, models, attacks))
    print(f"\nProcessed {len(records)} task evaluations into {outdir}")
    return outdir


