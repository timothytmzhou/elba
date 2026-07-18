"""The run matrix and the upfront plan.

A Benchmark is one AgentDojo task evaluation. Benchmarks are independent so
the eval is embarrassingly parallel. Results land at

    <logdir>/rep<r>/<pipeline>/<suite>/<task>/<attack>/<injection>.json

which also serves as the resume cache.
"""

from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
REPO_ROOT = EVAL_DIR.parent

BENIGN = "none"
SUITES = ("slack",)
ATTACKS = ("direct", "important_instructions")
BENCHMARK_VERSION = "v1.2.2"
TASK_TIMEOUT_S = 600

# Suites whose typeguard IFC policy is written. The rest run no policy only.
TYPEGUARD_POLICY_SUITES = {"slack"}

# Mirrors the Haskell Config record, written out as the binary's config.json.
# A None seed skips the llm seed option, which some providers lack.
@dataclass(frozen=True)
class AgentConfig:
    modelName: str
    systemPrompt: str
    maxAttempts: int
    maxDepth: int
    seed: int | None = None
    reasoningEffort: str | None = None


# A None camel_model means CaMeL cannot run this model, typeguard only.
@dataclass(frozen=True)
class Model:
    name: str
    agent_config: AgentConfig
    camel_model: str | None = None
    display: str = ""
    camel_reasoning: bool = False
    attack_model_name: str = "AI assistant"


def load_model(path: str | Path) -> Model:
    raw = json.loads(Path(path).read_text())
    return Model(
        name=raw["name"], camel_model=raw.get("camel_model"),
        agent_config=AgentConfig(**raw["agent_config"]),
        display=raw.get("display") or raw["name"],
        camel_reasoning=raw.get("camel_reasoning", False),
        attack_model_name=raw.get("attack_model_name", "AI assistant"))


@dataclass(frozen=True)
class Benchmark:
    system: str
    variant: str
    model: str
    rep: int
    suite: str
    task_id: str
    attack: str = BENIGN
    injection_task_id: str = BENIGN


def is_benign(b: Benchmark) -> bool:
    return b.attack == BENIGN


# Our result directory, one segment, the same shape for every system.
def pipeline_name(b: Benchmark) -> str:
    return f"{b.system}-{b.variant}-{b.model}"


def slug(b: Benchmark) -> str:
    return "-".join([pipeline_name(b), f"rep{b.rep}", b.suite, b.task_id,
                     b.attack, b.injection_task_id])


def result_path(b: Benchmark, logdir: Path) -> Path:
    return (logdir / f"rep{b.rep}" / pipeline_name(b) / b.suite / b.task_id
            / b.attack / f"{b.injection_task_id}.json")


def suite_tasks(suite: str, benchmark_version: str = BENCHMARK_VERSION):
    from agentdojo.task_suite.load_suites import get_suite

    s = get_suite(benchmark_version, suite)
    return list(s.user_tasks.keys()), list(s.injection_tasks.keys())


def expand(models: list[Model], suites: list[str], attacks: list[str], repeats: int,
           systems=("typeguard", "camel")) -> list[Benchmark]:
    benchmarks = []
    for suite in suites:
        user_tasks, injection_tasks = suite_tasks(suite)
        for model in models:
            for system in systems:
                if system == "camel" and not model.camel_model:
                    continue
                variants = (["nopolicy"] if system == "typeguard"
                            and suite not in TYPEGUARD_POLICY_SUITES else ["policy", "nopolicy"])
                for variant in variants:
                    for rep in range(1, repeats + 1):
                        base = dict(system=system, variant=variant, model=model.name,
                                    rep=rep, suite=suite)
                        benchmarks += [Benchmark(task_id=ut, **base) for ut in user_tasks]
                        benchmarks += [Benchmark(task_id=ut, attack=a, injection_task_id=it, **base)
                                       for a in attacks for ut in user_tasks for it in injection_tasks]
    return benchmarks


# Utility False with an error covers denials and timeouts.
@dataclass(frozen=True)
class Result:
    utility: bool
    security: bool
    duration_s: float | None = None
    tokens: dict | None = None
    error: str | None = None
    final_output: str | None = None
    messages: list = field(default_factory=list)
    agent_transcript: str | None = None
    result_file: str = ""


def load_result(path: Path) -> Result | None:
    try:
        r = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    if r.get("utility") not in (True, False):
        return None
    final = next((blk.get("content") or blk.get("text", "")
                  for m in reversed(r.get("messages") or [])
                  if m.get("role") == "assistant"
                  for blk in (m.get("content") or []) if isinstance(blk, dict)), None)
    return Result(r["utility"], r["security"], r.get("duration"), r.get("tokens"),
                  r.get("error"), final, r.get("messages") or [],
                  r.get("agent_transcript"), str(path))


class Outcome(Enum):
    COMPLETED = "completed"
    TIMEOUT = "timeout"


@dataclass(frozen=True)
class RunReport:
    completed: int = 0
    timeout: int = 0


def split_cached(benchmarks: list[Benchmark],
                 logdir: Path) -> tuple[list[Benchmark], list[Benchmark]]:
    to_run, cached = [], []
    for b in benchmarks:
        (cached if load_result(result_path(b, logdir)) else to_run).append(b)
    return to_run, cached


def print_plan(to_run, cached, max_workers) -> None:
    counts = Counter((b.model, b.system, b.variant, b.suite, "benign" if is_benign(b) else "attack")
                     for b in to_run)
    header = f"{'model':<16}{'system':<11}{'variant':<10}{'suite':<11}{'benign':>7}{'attack':>7}"
    print("\n=== Run plan ===", header, "-" * len(header), sep="\n")
    for model, system, variant, suite in sorted({k[:4] for k in counts}):
        b = counts.get((model, system, variant, suite, "benign"), 0)
        a = counts.get((model, system, variant, suite, "attack"), 0)
        print(f"{model:<16}{system:<11}{variant:<10}{suite:<11}{b:>7}{a:>7}")
    print("-" * len(header))
    print(f"To run : {len(to_run)} task evaluations ({len(cached)} cached, skipped)")
    print(f"Wall   : ~{-(-len(to_run) // max(max_workers, 1))} task-times "
          f"at --max-workers={max_workers}\n")
