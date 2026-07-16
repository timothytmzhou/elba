"""LLM-free tests of the eval infrastructure.

Everything below runs against the scripted stub agent (stub_agent.py) or
synthetic result trees — no API credits. Covers: matrix expansion and resume,
the bridge protocol end-to-end through a real AgentDojo task (including the
per-task timeout), the parallel runner, statistics, the raw dump, and the
LaTeX table output.
"""

import json
import math
import subprocess
import sys
from pathlib import Path

import pytest

EVAL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL_DIR))

from experiment import Atom, Model, expand, split_cached  # noqa: E402
from execute import run_atoms, to_jsonable  # noqa: E402
from process import (  # noqa: E402
    clustered_utility_ci, load_results, newcombe_paired_diff, process,
    suite_table, t_quantile_975, wilson_interval,
)


def model(name="gpt-5.4-high") -> Model:
    return Model(
        name=name, display="GPT-5.4 (high)",
        agent_config={"modelName": "gpt-5.4", "reasoningEffort": "high", "seed": 0,
                      "systemPrompt": "", "maxAttempts": 3, "maxDepth": 7},
        camel_model="openai:gpt-5.4-2026-03-05", camel_reasoning=True,
        attack_model_name="AI assistant",
    )


# ---------------------------------------------------------------------------
# Matrix


def test_expand_slack_counts():
    atoms = expand([model()], ["slack"], ["direct", "important_instructions"], repeats=1)
    # 4 pipelines x (21 benign + 2*105 attack)
    assert len(atoms) == 4 * (21 + 210)
    assert len(set(atoms)) == len(atoms)


def test_expand_nonslack_has_no_typeguard_policy():
    atoms = expand([model()], ["workspace"], [], repeats=1)
    tg = {a.variant for a in atoms if a.system == "typeguard"}
    cm = {a.variant for a in atoms if a.system == "camel"}
    assert tg == {"nopolicy"} and cm == {"policy", "nopolicy"}


def test_pipeline_names_match_camel_convention():
    m = model()
    assert m.pipeline_name("camel", "policy") == "gpt-5.4-2026-03-05-high+camel"
    assert m.pipeline_name("camel", "nopolicy") == "gpt-5.4-2026-03-05-high+camel-nopolicy"
    assert m.pipeline_name("typeguard", "policy") == "typeguard-gpt-5.4-high"


def test_split_cached(tmp_path):
    m = model()
    models = {m.name: m}
    a1 = Atom("typeguard", "policy", m.name, 1, "slack", "user_task_0")
    a2 = Atom("typeguard", "policy", m.name, 1, "slack", "user_task_1")
    p = a1.result_path(tmp_path, models)
    p.parent.mkdir(parents=True)
    p.write_text(json.dumps({"utility": True, "security": True}))
    to_run, cached = split_cached([a1, a2], tmp_path, models)
    assert cached == [a1] and to_run == [a2]


# ---------------------------------------------------------------------------
# Statistics


def test_t_quantile_matches_known_values():
    # reference values from standard t tables
    for df, expected in [(5, 2.571), (10, 2.228), (20, 2.086), (100, 1.984)]:
        assert abs(t_quantile_975(df) - expected) < 0.01


def test_wilson_interval():
    lo, hi = wilson_interval(105, 105)  # perfect security score
    assert hi == 100.0 and 95.0 < lo < 97.5
    lo, hi = wilson_interval(0, 105)
    assert lo == 0.0 and hi < 5.0


def test_clustered_utility_ci():
    n, total, pct, hw = clustered_utility_ci([[True]] * 15 + [[False]] * 6)
    assert (n, total) == (15, 21) and abs(pct - 71.43) < 0.01 and 0 < hw < 25
    # k=3 repetitions: units averaged over reps
    n, total, pct, _ = clustered_utility_ci([[True, True, False]] * 10)
    assert (n, total) == (20, 30) and abs(pct - 66.67) < 0.01


def test_newcombe_paired():
    # identical outcomes -> CI centered at 0 and containing it
    pairs = [(True, True)] * 10 + [(False, False)] * 5
    diff, lo, hi = newcombe_paired_diff(pairs)
    assert diff == 0 and lo < 0 < hi
    # one-sided discordance -> positive difference
    diff, lo, hi = newcombe_paired_diff([(True, False)] * 5 + [(True, True)] * 10)
    assert diff > 0 and hi > diff


def test_to_jsonable_handles_agentdojo_types():
    import datetime
    from agentdojo.default_suites.v1.tools.types import CalendarEvent

    event = CalendarEvent(id_="1", title="t", description="d",
                          start_time=datetime.datetime(2026, 5, 26, 10, 0),
                          end_time=datetime.datetime(2026, 5, 26, 11, 0),
                          location=None, participants=[])
    encoded = json.dumps(to_jsonable({"e": event, "d": datetime.date(2026, 5, 26)}))
    assert "2026-05-26T10:00:00" in encoded


# ---------------------------------------------------------------------------
# End-to-end through the stub agent (real AgentDojo tasks, no LLM)


def stub_exe(tmp_path: Path, actions: list[dict]) -> str:
    """The worker passes --config <agent config>; wrap the stub so it reads
    our action script instead."""
    script = tmp_path / "actions.json"
    script.write_text(json.dumps({"actions": actions}))
    wrapper = tmp_path / "stub.sh"
    wrapper.write_text(f"#!/bin/bash\nexec {sys.executable} "
                       f"{EVAL_DIR / 'stub_agent.py'} --config {script} "
                       '--log-path "${4:-/dev/null}"\n')
    wrapper.chmod(0o755)
    return str(wrapper)


@pytest.fixture()
def slack_run(tmp_path):
    """Run benign + attacked slack atoms through the real worker/runner."""
    m = model()
    models = {m.name: m}
    exe = stub_exe(tmp_path, [
        {"call": "get_webpage", "args": {"url": "www.informations.com"}},
        {"done": "I read the page."},
    ])
    atoms = [
        Atom("typeguard", "policy", m.name, 1, "slack", "user_task_0"),
        Atom("typeguard", "policy", m.name, 1, "slack", "user_task_0",
             attack="important_instructions", injection_task_id="injection_task_1"),
    ]
    logdir = tmp_path / "logs"
    import execute
    orig = execute.resolve_typeguard_exes
    execute.resolve_typeguard_exes = lambda atoms, build=True: {
        "agentdojo-slack-secure": exe, "agentdojo-slack": exe}
    try:
        report = run_atoms(atoms, models, logdir, "v1.2.2", timeout_s=60,
                           max_workers=2, build=False)
    finally:
        execute.resolve_typeguard_exes = orig
    return models, logdir, report


def test_worker_end_to_end(slack_run):
    models, logdir, report = slack_run
    assert report["completed"] == 2 and not report["crashed"]
    benign = json.loads(
        (logdir / "rep1/typeguard-gpt-5.4-high/slack/user_task_0/none/none.json").read_text())
    # user_task_0 is exactly "read www.informations.com" => utility True
    assert benign["utility"] is True
    assert benign["tokens"] is None or "input" in benign["tokens"]
    attacked = json.loads(
        (logdir / "rep1/typeguard-gpt-5.4-high/slack/user_task_0/"
                  "important_instructions/injection_task_1.json").read_text())
    assert attacked["utility"] is True
    assert attacked["security"] is False  # stub never performs the injection goal


def test_processing_outputs(slack_run):
    models, logdir, _ = slack_run
    outdir = process(logdir, models, ["slack"], ["important_instructions"], repeats=1)
    dump = [json.loads(l) for l in (outdir / "dump.jsonl").read_text().splitlines()]
    assert len(dump) == 2
    rec = next(r for r in dump if r["attack"] == "none")
    assert rec["utility"] is True and rec["final_output"] == "I read the page."
    assert rec["duration_s"] is not None

    tex = (outdir / "table_slack.tex").read_text()
    assert r"\begin{table}" in tex and r"\toprule" in tex
    assert "TypeGuard" in tex
    assert r"1/1 (100.0\%" in tex  # benign utility from the single task
    assert "1/1 [" in tex  # security: 1 of 1 pair resisted, Wilson bracket


def test_timeout_writes_failure(tmp_path):
    m = model()
    models = {m.name: m}
    exe = stub_exe(tmp_path, [{"sleep": 60}, {"done": "too late"}])
    atom = Atom("typeguard", "policy", m.name, 1, "slack", "user_task_0")
    import execute
    orig = execute.resolve_typeguard_exes
    execute.resolve_typeguard_exes = lambda atoms, build=True: {"agentdojo-slack-secure": exe}
    try:
        report = run_atoms([atom], models, tmp_path / "logs", "v1.2.2",
                           timeout_s=3, max_workers=1, build=False)
    finally:
        execute.resolve_typeguard_exes = orig
    result = json.loads(atom.result_path(tmp_path / "logs", models).read_text())
    assert result["utility"] is False
    assert report["completed"] + report["timeout"] == 1


# ---------------------------------------------------------------------------
# Table shape on a synthetic full matrix


def test_suite_table_full_matrix(tmp_path):
    m = model()
    models = {m.name: m}
    attacks = ["direct", "important_instructions"]
    records = []
    from experiment import suite_tasks
    user_tasks, injection_tasks = suite_tasks("slack")
    for system, variant in [("typeguard", "policy"), ("typeguard", "nopolicy"),
                            ("camel", "policy"), ("camel", "nopolicy")]:
        for ut in user_tasks:
            records.append(dict(rep=1, system=system, variant=variant, model=m.name,
                                suite="slack", task=ut, attack="none",
                                injection_task="none", utility=True, security=True))
            for attack in attacks:
                for it in injection_tasks:
                    records.append(dict(
                        rep=1, system=system, variant=variant, model=m.name,
                        suite="slack", task=ut, attack=attack, injection_task=it,
                        utility=True, security=(variant == "nopolicy")))
    tex = suite_table(records, "slack", models, attacks, repeats=1)
    # all four system rows present, incl. the previously-missing
    # no-policy-under-attack cells
    for label in ["TypeGuard", "TypeGuard (no policy)", "CaMeL", "CaMeL (no policy)"]:
        assert label in tex
    assert r"105/105 (100.0\%" in tex  # attacked utility, populated for nopolicy
    assert "105/105 [96." in tex       # policy rows resist all 105 pairs (Wilson)
    assert "0/105 [0.0," in tex        # nopolicy rows resist none
