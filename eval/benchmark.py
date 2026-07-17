"""The run matrix and the upfront plan.

A Benchmark is one AgentDojo task evaluation. Benchmarks are independent so
the eval is embarrassingly parallel. Results land at

    <logdir>/rep<r>/<pipeline>/<suite>/<task>/<attack>/<injection>.json

which also serves as the resume cache.
"""

from __future__ import annotations

import json
from collections import Counter
from dataclasses import asdict, dataclass, field
from enum import Enum
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
REPO_ROOT = EVAL_DIR.parent

BENIGN = "none"
SUITES = ("slack", "workspace", "travel", "banking")
ATTACKS = ("direct", "important_instructions")
BENCHMARK_VERSION = "v1.2.2"
TASK_TIMEOUT_S = 600

# Suites whose typeguard IFC policy is written. The rest run no policy only.
TYPEGUARD_POLICY_SUITES = {"slack"}

# Fallback token counts per task for the estimate before any run has data.
DEFAULT_TOKENS_PER_TASK = {"input": 30_000, "output": 5_000}
# CaMeL spends extra on its quarantined LLM round trips.
CAMEL_TOKEN_MULTIPLIER = 1.5


@dataclass(frozen=True)
class Model:
    name: str
    display: str
    agent_config: dict
    camel_model: str
    camel_reasoning: bool
    attack_model_name: str

    @staticmethod
    def load(path: str | Path) -> "Model":
        raw = json.loads(Path(path).read_text())
        return Model(
            raw["name"], raw.get("display", raw["name"]), raw["agent_config"],
            raw["camel_model"], raw.get("camel_reasoning", False),
            raw.get("attack_model_name", "AI assistant"))

    def pipeline_name(self, system: str, variant: str) -> str:
        # The camel names match upstream's own suffixes. +camel is the fresh
        # no policy pass and +camel+secpol replays it with policies.
        if system == "typeguard":
            return f"typeguard{'' if variant == 'policy' else '-nopolicy'}-{self.name}"
        model_id = self.camel_model.split(":")[1]
        base = f"{model_id}-{self.agent_config.get('reasoningEffort')}" if self.camel_reasoning else model_id
        return base + ("+camel+secpol" if variant == "policy" else "+camel")


@dataclass(frozen=True)
class Benchmark:
    """One task evaluation. Carries its own Model, so it fully describes what
    to run and can serialize itself to a worker."""
    system: str
    variant: str
    model: Model
    rep: int
    suite: str
    task_id: str
    attack: str = BENIGN
    injection_task_id: str = BENIGN

    @property
    def benign(self) -> bool:
        return self.attack == BENIGN

    @property
    def pipeline_name(self) -> str:
        return self.model.pipeline_name(self.system, self.variant)

    @property
    def slug(self) -> str:
        return "-".join([self.system, self.variant, self.model.name, f"rep{self.rep}",
                         self.suite, self.task_id, self.attack, self.injection_task_id])

    def result_path(self, logdir: Path) -> Path:
        return (logdir / f"rep{self.rep}" / self.pipeline_name / self.suite / self.task_id
                / self.attack / f"{self.injection_task_id}.json")

    def to_json(self) -> str:
        return json.dumps(asdict(self))

    @staticmethod
    def from_json(s: str) -> Benchmark:
        d = json.loads(s)
        return Benchmark(model=Model(**d.pop("model")), **d)


def suite_tasks(suite: str, benchmark_version: str = BENCHMARK_VERSION):
    from agentdojo.task_suite.load_suites import get_suite

    s = get_suite(benchmark_version, suite)
    return list(s.user_tasks.keys()), list(s.injection_tasks.keys())


def expand(models, suites, attacks, repeats, systems=("typeguard", "camel")) -> list[Benchmark]:
    benchmarks = []
    for suite in suites:
        user_tasks, injection_tasks = suite_tasks(suite)
        for model in models:
            for system in systems:
                variants = (["nopolicy"] if system == "typeguard"
                            and suite not in TYPEGUARD_POLICY_SUITES else ["policy", "nopolicy"])
                for variant in variants:
                    for rep in range(1, repeats + 1):
                        base = dict(system=system, variant=variant, model=model,
                                    rep=rep, suite=suite)
                        benchmarks += [Benchmark(task_id=ut, **base) for ut in user_tasks]
                        benchmarks += [Benchmark(task_id=ut, attack=a, injection_task_id=it, **base)
                                       for a in attacks for ut in user_tasks for it in injection_tasks]
    return benchmarks


@dataclass(frozen=True)
class Result:
    """A task's output, kept separate from the Benchmark that produced it.
    Utility False with an error covers both policy denials and timeouts."""
    utility: bool
    security: bool
    duration_s: float | None = None
    tokens: dict | None = None
    error: str | None = None
    final_output: str | None = None
    messages: list = field(default_factory=list)
    agent_transcript: str | None = None
    result_file: str = ""

    @staticmethod
    def load(path: Path) -> Result | None:
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


def split_cached(benchmarks, logdir):
    to_run, cached = [], []
    for b in benchmarks:
        (cached if Result.load(b.result_path(logdir)) else to_run).append(b)
    return to_run, cached


PRICING_URL = "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json"
PRICING_CACHE = EVAL_DIR / "pricing.json"


def load_pricing() -> dict:
    """OpenAI prices per million tokens, fetched once and cached gitignored."""
    if PRICING_CACHE.exists():
        return json.loads(PRICING_CACHE.read_text())
    import time
    import urllib.request

    raw = json.load(urllib.request.urlopen(PRICING_URL, timeout=30))
    models = {name: {"input": m["input_cost_per_token"] * 1e6,
                     "output": m["output_cost_per_token"] * 1e6}
              for name, m in raw.items()
              if m.get("litellm_provider") == "openai"
              and "input_cost_per_token" in m and "output_cost_per_token" in m}
    pricing = {"source": PRICING_URL, "retrieved": time.strftime("%Y-%m-%d"), "models": models}
    PRICING_CACHE.write_text(json.dumps(pricing, indent=1))
    return pricing


def price_for(camel_model: str, pricing: dict) -> dict:
    # Dated snapshots like gpt-5.4-2026-03-05 fall back to the gpt-5.4 row.
    model_id = camel_model.split(":")[1]
    table = pricing["models"]
    if model_id in table:
        return table[model_id]
    matches = [k for k in table if model_id.startswith(k)]
    if not matches:
        raise KeyError(f"no price for {model_id!r}. delete eval/pricing.json to refetch")
    return table[max(matches, key=len)]


def measured_tokens_per_task(logdir: Path) -> dict | None:
    total, n = {"input": 0, "output": 0}, 0
    for path in logdir.glob("rep*/typeguard*/**/*.json"):
        try:
            tokens = json.loads(path.read_text()).get("tokens")
        except (OSError, json.JSONDecodeError):
            continue
        if tokens and tokens.get("input"):
            total["input"] += tokens["input"]
            total["output"] += tokens["output"]
            n += 1
    if n < 5:
        return None
    return {"input": total["input"] // n, "output": total["output"] // n, "samples": n}


def estimate_cost(benchmarks, logdir) -> tuple[float, str]:
    pricing = load_pricing()
    measured = measured_tokens_per_task(logdir)
    per_task = measured or DEFAULT_TOKENS_PER_TASK
    basis = (f"measured over {measured['samples']} tasks" if measured
             else f"assuming {per_task['input'] // 1000}k in and {per_task['output'] // 1000}k out per task")
    cost = 0.0
    for b in benchmarks:
        # camel policy replays the recorded run and costs no LLM calls
        if b.system == "camel" and b.variant == "policy":
            continue
        price = price_for(b.model.camel_model, pricing)
        mult = CAMEL_TOKEN_MULTIPLIER if b.system == "camel" else 1.0
        cost += mult * (per_task["input"] / 1e6 * price["input"]
                        + per_task["output"] / 1e6 * price["output"])
    return cost, f"{basis}. prices from {pricing['source']} retrieved {pricing['retrieved']}"


def print_plan(to_run, cached, logdir, max_workers) -> None:
    counts = Counter((b.model.name, b.system, b.variant, b.suite, "benign" if b.benign else "attack")
                     for b in to_run)
    header = f"{'model':<16}{'system':<11}{'variant':<10}{'suite':<11}{'benign':>7}{'attack':>7}"
    print("\n=== Run plan ===", header, "-" * len(header), sep="\n")
    for model, system, variant, suite in sorted({k[:4] for k in counts}):
        b = counts.get((model, system, variant, suite, "benign"), 0)
        a = counts.get((model, system, variant, suite, "attack"), 0)
        print(f"{model:<16}{system:<11}{variant:<10}{suite:<11}{b:>7}{a:>7}")
    print("-" * len(header))
    cost, basis = estimate_cost(to_run, logdir)
    print(f"To run : {len(to_run)} task evaluations ({len(cached)} cached, skipped)")
    print(f"Cost   : ~${cost:,.0f}  [{basis}]")
    print(f"Wall   : ~{-(-len(to_run) // max(max_workers, 1))} task-times "
          f"at --max-workers={max_workers}\n")
