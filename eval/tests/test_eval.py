"""Tests of the eval infrastructure with no LLM calls.

The end-to-end tests run the real agent binary and interpreter, with a
scripted stand in for the llm CLI placed first on PATH.
"""

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

EVAL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL_DIR))

from benchmark import Benchmark, Model, REPO_ROOT, expand, split_cached  # noqa: E402
from bridge import to_jsonable  # noqa: E402
from run import run_benchmarks, typeguard_exe  # noqa: E402
from process import newcombe_paired_diff, process, suite_table  # noqa: E402


def model(name="gpt-5.4-high") -> Model:
    return Model(
        name=name, display="GPT-5.4 (high)",
        agent_config={"modelName": "gpt-5.4", "reasoningEffort": "high", "seed": 0,
                      "systemPrompt": "", "maxAttempts": 3, "maxDepth": 7},
        camel_model="openai:gpt-5.4-2026-03-05", camel_reasoning=True,
        attack_model_name="ChatGPT",
    )


def test_expand_slack_counts():
    atoms = expand([model()], ["slack"], ["direct", "important_instructions"], repeats=1)
    assert len(atoms) == 4 * (21 + 210)
    assert len(set(atoms)) == len(atoms)


def test_expand_nonslack_has_no_typeguard_policy():
    atoms = expand([model()], ["workspace"], [], repeats=1)
    tg = {a.variant for a in atoms if a.system == "typeguard"}
    cm = {a.variant for a in atoms if a.system == "camel"}
    assert tg == {"nopolicy"} and cm == {"policy", "nopolicy"}


def test_pipeline_names_match_camel_convention():
    m = model()
    assert m.pipeline_name("camel", "policy") == "gpt-5.4-2026-03-05-high+camel+secpol"
    assert m.pipeline_name("camel", "nopolicy") == "gpt-5.4-2026-03-05-high+camel"
    assert m.pipeline_name("typeguard", "policy") == "typeguard-gpt-5.4-high"


def test_split_cached(tmp_path):
    m = model()
    models = {m.name: m}
    a1 = Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_0")
    a2 = Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_1")
    p = a1.result_path(tmp_path, models)
    p.parent.mkdir(parents=True)
    p.write_text(json.dumps({"utility": True, "security": True}))
    to_run, cached = split_cached([a1, a2], tmp_path, models)
    assert cached == [a1] and to_run == [a2]


def test_newcombe_paired():
    pairs = [(True, True)] * 10 + [(False, False)] * 5
    diff, lo, hi = newcombe_paired_diff(pairs)
    assert diff == 0 and lo < 0 < hi
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


# The vetted secure program for slack user_task_0 from the reference tests.
PROGRAM = 'do { _ <- getWebpage "www.informations.com"; return "I read the page." }'


@pytest.fixture(scope="session")
def agent_exe():
    try:
        return typeguard_exe()
    except (FileNotFoundError, subprocess.CalledProcessError):
        pytest.skip("the agentdojo binary cannot be built here")


@pytest.fixture()
def mock_llm(tmp_path, monkeypatch):
    # Writes a scripted llm CLI and puts it first on PATH for the workers.
    def script(body: str) -> None:
        exe = tmp_path / "bin" / "llm"
        exe.parent.mkdir(exist_ok=True)
        exe.write_text(f"#!/bin/bash\ncat > /dev/null\n{body}\n")
        exe.chmod(0o755)
        monkeypatch.setenv("PATH", f"{exe.parent}:{os.environ['PATH']}")
    return script


@pytest.fixture()
def slack_run(tmp_path, agent_exe, mock_llm):
    # Run benign and attacked slack benchmarks through the real runner.
    m = model()
    models = {m.name: m}
    mock_llm(f"cat <<'CODE'\n{PROGRAM}\nCODE")
    benchmarks = [
        Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_0"),
        Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_0",
                  attack="important_instructions", injection_task_id="injection_task_1"),
    ]
    logdir = tmp_path / "logs"
    report = run_benchmarks(benchmarks, models, logdir, "v1.2.2", timeout_s=300,
                            max_workers=2, build=False)
    return models, logdir, report


def test_worker_end_to_end(slack_run):
    models, logdir, report = slack_run
    assert report["completed"] == 2 and not report["crashed"]
    benign = json.loads(
        (logdir / "rep1/typeguard-gpt-5.4-high/slack/user_task_0/none/none.json").read_text())
    assert benign["utility"] is True
    assert benign["tokens"] is None or "input" in benign["tokens"]
    attacked = json.loads(
        (logdir / "rep1/typeguard-gpt-5.4-high/slack/user_task_0/"
                  "important_instructions/injection_task_1.json").read_text())
    assert attacked["utility"] is True
    assert attacked["security"] is False  # stub never performs the injection


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
    assert r"1/1 (100.0\%)" in tex
    assert " & 1/1 " in tex


def test_subagent_recursion(tmp_path, agent_exe, mock_llm):
    # The parent emission delegates to a subagent, whose own emission
    # answers. Exercises the recursive mkAgent path where the resolved
    # tools ride along in the Env instead of resolving again.
    count = tmp_path / "calls"
    mock_llm(f"""N=$(cat {count} 2>/dev/null || echo 0)
echo $((N+1)) > {count}
if [ "$N" = 0 ]; then cat <<'CODE'
subagent "Return exactly the string hello." "" :: DC String
CODE
else cat <<'CODE'
return "hello"
CODE
fi""")
    proc = subprocess.run(
        [agent_exe, "--suite", "slack", "--secure"],
        input='{"prompt": "Delegate to a subagent."}\n',
        capture_output=True, text=True, timeout=300, cwd=REPO_ROOT,
        env=os.environ.copy())
    assert json.loads(proc.stdout.splitlines()[0]) == {"done": "hello"}, proc.stdout
    assert count.read_text().strip() == "2"


def test_timeout_writes_failure(tmp_path, agent_exe, mock_llm):
    m = model()
    models = {m.name: m}
    mock_llm("sleep 60")
    bench = Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_0")
    report = run_benchmarks([bench], models, tmp_path / "logs", "v1.2.2",
                            timeout_s=5, max_workers=1, build=False)
    result = json.loads(bench.result_path(tmp_path / "logs", models).read_text())
    assert result["utility"] is False
    assert report["timeout"] == 1


def test_suite_table_full_matrix(tmp_path):
    m = model()
    models = {m.name: m}
    attacks = ["direct", "important_instructions"]
    records = []
    from benchmark import suite_tasks
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
    # all four system rows including the no policy under attack cells
    for label in ["TypeGuard", "TypeGuard (no policy)", "CaMeL", "CaMeL (no policy)"]:
        assert label in tex
    assert r"105/105 (100.0\%)" in tex
    assert " & 0/105 " in tex
