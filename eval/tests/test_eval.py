"""Tests of the eval infrastructure with no LLM calls.

The end-to-end tests run the real agent binary and interpreter, with a
scripted stand in for the llm CLI wired in through llmCommand.
"""

import json
import subprocess
import sys
from dataclasses import asdict
from pathlib import Path

import pytest

EVAL_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(EVAL_DIR))

from benchmark import (  # noqa: E402
    AgentConfig, Benchmark, Model, REPO_ROOT, Result, expand, pipeline_name, result_path,
    slug, split_cached)
from bridge import to_jsonable  # noqa: E402
from run import run_benchmarks, typeguard_exe  # noqa: E402
from process import newcombe_paired_diff, process, suite_table  # noqa: E402


def model(name="gpt-5.4-high", llm_command=None) -> Model:
    return Model(
        name=name, display="GPT-5.4 (high)",
        agent_config=AgentConfig(modelName="gpt-5.4", reasoningEffort="high", seed=0,
                                 llmCommand=llm_command),
        camel_model="openai:gpt-5.4-2026-03-05",
        attack_model_name="ChatGPT",
    )


def configs_for(m: Model, tmp_path: Path) -> dict[str, str]:
    # Workers load their model from a config file, so write one.
    path = tmp_path / f"{m.name}.json"
    path.write_text(json.dumps(asdict(m)))
    return {m.name: str(path)}


def test_expand_slack_counts():
    atoms = expand([model()], ["slack"], ["direct", "important_instructions"], repeats=1)
    assert len(atoms) == 4 * (21 + 210)
    assert len({slug(a) for a in atoms}) == len(atoms)


def test_expand_nonslack_has_no_typeguard_policy():
    atoms = expand([model()], ["workspace"], [], repeats=1)
    tg = {a.variant for a in atoms if a.system == "typeguard"}
    cm = {a.variant for a in atoms if a.system == "camel"}
    assert tg == {"nopolicy"} and cm == {"policy", "nopolicy"}


def test_pipeline_name_is_uniform():
    b = Benchmark("camel", "policy", "gpt-5.4-high", 1, "slack", "user_task_0")
    assert pipeline_name(b) == "camel-policy-gpt-5.4-high"
    assert pipeline_name(Benchmark("typeguard", "nopolicy", "gpt-4o", 1, "slack", "t")) \
        == "typeguard-nopolicy-gpt-4o"


def test_split_cached(tmp_path):
    m = model()
    a1 = Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_0")
    a2 = Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_1")
    p = result_path(a1, tmp_path)
    p.parent.mkdir(parents=True)
    p.write_text(json.dumps({"utility": True, "security": True}))
    to_run, cached = split_cached([a1, a2], tmp_path)
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
def mock_llm(tmp_path):
    # Writes a scripted llm CLI, wired in through the config's llmCommand.
    def script(body: str) -> str:
        exe = tmp_path / "bin" / "llm"
        exe.parent.mkdir(exist_ok=True)
        exe.write_text(f"#!/bin/bash\ncat > /dev/null\n{body}\n")
        exe.chmod(0o755)
        return str(exe)
    return script


@pytest.fixture()
def slack_run(tmp_path, agent_exe, mock_llm):
    # Run benign and attacked slack benchmarks through the real runner.
    m = model(llm_command=mock_llm(f"cat <<'CODE'\n{PROGRAM}\nCODE"))
    models = {m.name: m}
    benchmarks = [
        Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_0"),
        Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_0",
                  attack="important_instructions", injection_task_id="injection_task_1"),
    ]
    logdir = tmp_path / "logs"
    report = run_benchmarks(benchmarks, configs_for(m, tmp_path), logdir, "v1.2.2",
                            timeout_s=300, max_workers=2, build=False)
    return models, logdir, report


def test_worker_end_to_end(slack_run):
    models, logdir, report = slack_run
    assert report.completed == 2
    benign = json.loads(
        (logdir / "rep1/typeguard-policy-gpt-5.4-high/slack/user_task_0/none/none.json").read_text())
    assert benign["utility"] is True
    assert benign["tokens"] is None or "input" in benign["tokens"]
    attacked = json.loads(
        (logdir / "rep1/typeguard-policy-gpt-5.4-high/slack/user_task_0/"
                  "important_instructions/injection_task_1.json").read_text())
    assert attacked["utility"] is True
    assert attacked["security"] is False  # stub never performs the injection


def test_processing_outputs(slack_run):
    models, logdir, _ = slack_run
    outdir = process(logdir, models, ["slack"], ["important_instructions"], repeats=1)
    dump = [json.loads(l) for l in (outdir / "dump.jsonl").read_text().splitlines()]
    assert len(dump) == 2
    rec = next(r for r in dump if r["benchmark"]["attack"] == "none")
    assert rec["result"]["utility"] is True and rec["result"]["final_output"] == "I read the page."
    assert rec["result"]["duration_s"] is not None

    tex = (outdir / "table_slack.tex").read_text()
    assert r"\begin{table}" in tex and r"\toprule" in tex
    assert "TypeGuard" in tex
    assert r"1/1 (100.0\%)" in tex
    assert " & 1/1 " in tex


def test_subagent_recursion(tmp_path, agent_exe, mock_llm):
    # The parent emission delegates to a subagent whose own emission answers.
    count = tmp_path / "calls"
    llm = mock_llm(f"""N=$(cat {count} 2>/dev/null || echo 0)
echo $((N+1)) > {count}
if [ "$N" = 0 ]; then cat <<'CODE'
subagent "Return exactly the string hello." "" :: DC String
CODE
else cat <<'CODE'
return "hello"
CODE
fi""")
    config = tmp_path / "config.json"
    config.write_text(json.dumps(asdict(model(llm_command=llm).agent_config)))
    proc = subprocess.run(
        [agent_exe, "--suite", "slack", "--secure", "--config", str(config)],
        input='{"prompt": "Delegate to a subagent."}\n',
        capture_output=True, text=True, timeout=300, cwd=REPO_ROOT)
    assert json.loads(proc.stdout.splitlines()[0]) == {"done": "hello"}, proc.stdout
    assert count.read_text().strip() == "2"


def test_timeout_writes_failure(tmp_path, agent_exe, mock_llm):
    m = model(llm_command=mock_llm("sleep 60"))
    bench = Benchmark("typeguard", "policy", m.name, 1, "slack", "user_task_0")
    report = run_benchmarks([bench], configs_for(m, tmp_path), tmp_path / "logs", "v1.2.2",
                            timeout_s=5, max_workers=1, build=False)
    result = json.loads(result_path(bench, tmp_path / "logs").read_text())
    assert result["utility"] is False
    assert report.timeout == 1


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
            records.append((Benchmark(system, variant, m.name, 1, "slack", ut),
                            Result(utility=True, security=True)))
            for attack in attacks:
                for it in injection_tasks:
                    records.append((Benchmark(system, variant, m.name, 1, "slack", ut, attack, it),
                                    Result(utility=True, security=(variant == "nopolicy"))))
    tex = suite_table(records, "slack", models, attacks, repeats=1)
    # all four system rows including the no policy under attack cells
    for label in ["TypeGuard", "TypeGuard (no policy)", "CaMeL", "CaMeL (no policy)"]:
        assert label in tex
    assert r"105/105 (100.0\%)" in tex
    assert " & 0/105 " in tex
