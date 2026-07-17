"""The run matrix and the upfront plan.

A Benchmark is one AgentDojo task evaluation. Benchmarks are independent so
the eval is embarrassingly parallel. Results land at

    <logdir>/rep<r>/<pipeline>/<suite>/<task>/<attack>/<injection>.json

which also serves as the resume cache.
"""

from __future__ import annotations

import json
from collections import Counter
from dataclasses import dataclass
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
        # CaMeL builds this name itself so the camel branch must match its
        # patched make_tools_pipeline.
        if system == "typeguard":
            return f"typeguard{'' if variant == 'policy' else '-nopolicy'}-{self.name}"
        model_id = self.camel_model.split(":")[1]
        base = f"{model_id}-{self.agent_config.get('reasoningEffort')}" if self.camel_reasoning else model_id
        return base + ("+camel" if variant == "policy" else "+camel-nopolicy")


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

    @property
    def benign(self) -> bool:
        return self.attack == BENIGN

    def result_path(self, logdir: Path, models: dict[str, Model]) -> Path:
        pipeline = models[self.model].pipeline_name(self.system, self.variant)
        return (logdir / f"rep{self.rep}" / pipeline / self.suite / self.task_id
                / self.attack / f"{self.injection_task_id}.json")


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
                        base = dict(system=system, variant=variant, model=model.name,
                                    rep=rep, suite=suite)
                        benchmarks += [Benchmark(task_id=ut, **base) for ut in user_tasks]
                        benchmarks += [Benchmark(task_id=ut, attack=a, injection_task_id=it, **base)
                                       for a in attacks for ut in user_tasks for it in injection_tasks]
    return benchmarks


def is_finalized(path: Path) -> bool:
    try:
        return json.loads(path.read_text()).get("utility") in (True, False)
    except (OSError, json.JSONDecodeError):
        return False


def split_cached(benchmarks, logdir, models):
    cached = [b for b in benchmarks if is_finalized(b.result_path(logdir, models))]
    done = set(cached)
    return [b for b in benchmarks if b not in done], cached


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


def estimate_cost(benchmarks, models, logdir) -> tuple[float, str]:
    pricing = load_pricing()
    measured = measured_tokens_per_task(logdir)
    per_task = measured or DEFAULT_TOKENS_PER_TASK
    basis = (f"measured over {measured['samples']} tasks" if measured
             else f"assuming {per_task['input'] // 1000}k in and {per_task['output'] // 1000}k out per task")
    cost = 0.0
    for b in benchmarks:
        price = price_for(models[b.model].camel_model, pricing)
        mult = CAMEL_TOKEN_MULTIPLIER if b.system == "camel" else 1.0
        cost += mult * (per_task["input"] / 1e6 * price["input"]
                        + per_task["output"] / 1e6 * price["output"])
    return cost, f"{basis}. prices from {pricing['source']} retrieved {pricing['retrieved']}"


def print_plan(to_run, cached, models, logdir, max_workers) -> None:
    counts = Counter((b.model, b.system, b.variant, b.suite, "benign" if b.benign else "attack")
                     for b in to_run)
    header = f"{'model':<16}{'system':<11}{'variant':<10}{'suite':<11}{'benign':>7}{'attack':>7}"
    print("\n=== Run plan ===", header, "-" * len(header), sep="\n")
    for model, system, variant, suite in sorted({k[:4] for k in counts}):
        b = counts.get((model, system, variant, suite, "benign"), 0)
        a = counts.get((model, system, variant, suite, "attack"), 0)
        print(f"{model:<16}{system:<11}{variant:<10}{suite:<11}{b:>7}{a:>7}")
    print("-" * len(header))
    cost, basis = estimate_cost(to_run, models, logdir)
    print(f"To run : {len(to_run)} task evaluations ({len(cached)} cached, skipped)")
    print(f"Cost   : ~${cost:,.0f}  [{basis}]")
    print(f"Wall   : ~{-(-len(to_run) // max(max_workers, 1))} task-times "
          f"at --max-workers={max_workers}\n")
