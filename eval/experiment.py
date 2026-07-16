"""Experiment definition: which task evaluations ("atoms") to run.

An atom is one AgentDojo task evaluation:
    (system, variant, model, repeat, suite, attack, user task, injection task)
where system is "typeguard" (ours) or "camel", and variant is "policy" or
"nopolicy". Atoms are independent, which is what makes the eval
embarrassingly parallel. Results land in AgentDojo's standard layout,

    <logdir>/rep<r>/<pipeline_name>/<suite>/<task>/<attack>/<injection>.json

which doubles as the resume cache.

This module also computes the upfront plan: how many atoms will run and a
cost estimate priced from OpenAI's published rates (pricing.json). Token
usage per task is measured from cached results when any exist; otherwise a
documented default assumption is used.
"""

from __future__ import annotations

import json
from dataclasses import dataclass
from pathlib import Path

EVAL_DIR = Path(__file__).resolve().parent
REPO_ROOT = EVAL_DIR.parent

BENIGN = "none"
SUITES = ("slack", "workspace", "travel", "banking")
ATTACKS = ("direct", "important_instructions")
BENCHMARK_VERSION = "v1.2.2"
TASK_TIMEOUT_S = 600  # 10-minute per-task budget, as in the paper

# Suites whose IFC policies exist for our system. workspace/travel/banking
# policies are hand-written later (see examples/ifc/*/policy); until then
# only the no-policy variant runs there.
TYPEGUARD_POLICY_SUITES = {"slack"}

# Tokens one task evaluation burns (whole agent loop). Used for the cost
# estimate only, and only when no measured data is available yet.
DEFAULT_TOKENS_PER_TASK = {"input": 30_000, "output": 5_000}
# CaMeL's privileged+quarantined LLM round trips cost extra vs. ours.
CAMEL_TOKEN_MULTIPLIER = 1.5


@dataclass(frozen=True)
class Model:
    """One model configuration (one JSON file under eval/configs/)."""

    name: str  # slug used in paths, e.g. "gpt-5.4-high"
    display: str  # table row label, e.g. "GPT-5.4 (high)"
    agent_config: dict  # Haskell agent Config (modelName, reasoningEffort, ...)
    camel_model: str  # e.g. "openai:gpt-5.4-2026-03-05"
    camel_reasoning: bool
    attack_model_name: str  # name embedded in injections by agentdojo attacks

    @staticmethod
    def load(path: str | Path) -> "Model":
        raw = json.loads(Path(path).read_text())
        return Model(
            name=raw["name"],
            display=raw.get("display", raw["name"]),
            agent_config=raw["agent_config"],
            camel_model=raw["camel_model"],
            camel_reasoning=raw.get("camel_reasoning", False),
            attack_model_name=raw.get("attack_model_name", "AI assistant"),
        )

    def pipeline_name(self, system: str, variant: str) -> str:
        """Directory name results are stored under.

        For CaMeL this must mirror the naming in its (patched)
        make_tools_pipeline, since CaMeL builds the name itself.
        """
        if system == "typeguard":
            return f"typeguard{'' if variant == 'policy' else '-nopolicy'}-{self.name}"
        model_id = self.camel_model.split(":")[1]
        effort = self.agent_config.get("reasoningEffort")
        base = f"{model_id}-{effort}" if self.camel_reasoning else model_id
        return base + ("+camel" if variant == "policy" else "+camel-nopolicy")


@dataclass(frozen=True)
class Atom:
    system: str
    variant: str
    model: str
    rep: int
    suite: str
    task_id: str
    attack: str = BENIGN
    injection_task_id: str = BENIGN

    def result_path(self, logdir: Path, models: dict[str, Model]) -> Path:
        pipeline = models[self.model].pipeline_name(self.system, self.variant)
        return (
            logdir / f"rep{self.rep}" / pipeline / self.suite
            / self.task_id / self.attack / f"{self.injection_task_id}.json"
        )


def suite_tasks(suite: str, benchmark_version: str = BENCHMARK_VERSION) -> tuple[list[str], list[str]]:
    from agentdojo.task_suite.load_suites import get_suite

    s = get_suite(benchmark_version, suite)
    return list(s.user_tasks.keys()), list(s.injection_tasks.keys())


def variants(system: str, suite: str) -> list[str]:
    if system == "typeguard" and suite not in TYPEGUARD_POLICY_SUITES:
        return ["nopolicy"]
    return ["policy", "nopolicy"]


def expand(
    models: list[Model],
    suites: list[str],
    attacks: list[str],
    repeats: int,
    systems: list[str] = ("typeguard", "camel"),
) -> list[Atom]:
    atoms = []
    for suite in suites:
        user_tasks, injection_tasks = suite_tasks(suite)
        for model in models:
            for system in systems:
                for variant in variants(system, suite):
                    for rep in range(1, repeats + 1):
                        base = dict(
                            system=system, variant=variant, model=model.name,
                            rep=rep, suite=suite,
                        )
                        atoms += [Atom(task_id=ut, **base) for ut in user_tasks]
                        atoms += [
                            Atom(task_id=ut, attack=attack, injection_task_id=it, **base)
                            for attack in attacks
                            for ut in user_tasks
                            for it in injection_tasks
                        ]
    return atoms


def is_finalized(path: Path) -> bool:
    try:
        return json.loads(path.read_text()).get("utility") in (True, False)
    except (OSError, json.JSONDecodeError):
        return False


def split_cached(atoms: list[Atom], logdir: Path, models: dict[str, Model]):
    cached = [a for a in atoms if is_finalized(a.result_path(logdir, models))]
    done = set(cached)
    return [a for a in atoms if a not in done], cached


# ---------------------------------------------------------------------------
# Plan + cost estimate


def published_pricing() -> dict:
    """OpenAI's published per-1M-token prices (see pricing.json for source)."""
    return json.loads((EVAL_DIR / "pricing.json").read_text())


def price_for(camel_model: str, pricing: dict) -> dict:
    model_id = camel_model.split(":")[1]
    # exact match first, then longest matching prefix (dated snapshots like
    # gpt-5.4-2026-03-05 fall back to the gpt-5.4 price row)
    table = pricing["models"]
    if model_id in table:
        return table[model_id]
    matches = [k for k in table if model_id.startswith(k)]
    if not matches:
        raise KeyError(
            f"no published price for {model_id!r} in eval/pricing.json; "
            f"add a row (source: {pricing['source']})"
        )
    return table[max(matches, key=len)]


def measured_tokens_per_task(logdir: Path) -> dict | None:
    """Average measured token usage over finished typeguard results, if any."""
    total = {"input": 0, "output": 0}
    n = 0
    for path in logdir.glob("rep*/typeguard*/**/*.json"):
        try:
            tokens = json.loads(path.read_text()).get("tokens")
        except (OSError, json.JSONDecodeError):
            continue
        if tokens and tokens.get("input"):
            total["input"] += tokens["input"]
            total["output"] += tokens["output"]
            n += 1
    if n < 5:  # too little data to be meaningful
        return None
    return {"input": total["input"] // n, "output": total["output"] // n, "samples": n}


def estimate_cost(atoms: list[Atom], models: dict[str, Model], logdir: Path) -> tuple[float, str]:
    pricing = published_pricing()
    measured = measured_tokens_per_task(logdir)
    per_task = measured or DEFAULT_TOKENS_PER_TASK
    basis = (
        f"measured avg over {measured['samples']} finished tasks"
        if measured
        else f"default assumption {per_task['input'] // 1000}k in / {per_task['output'] // 1000}k out per task"
    )
    cost = 0.0
    for atom in atoms:
        price = price_for(models[atom.model].camel_model, pricing)
        mult = CAMEL_TOKEN_MULTIPLIER if atom.system == "camel" else 1.0
        cost += mult * (
            per_task["input"] / 1e6 * price["input"]
            + per_task["output"] / 1e6 * price["output"]
        )
    return cost, f"{basis}; prices from {pricing['source']} (retrieved {pricing['retrieved']})"


def print_plan(to_run: list[Atom], cached: list[Atom], models: dict[str, Model],
               logdir: Path, max_workers: int) -> None:
    from collections import Counter

    counts = Counter(
        (a.model, a.system, a.variant, a.suite, "attack" if a.attack != BENIGN else "benign")
        for a in to_run
    )
    header = f"{'model':<16}{'system':<11}{'variant':<10}{'suite':<11}{'benign':>7}{'attack':>7}"
    print("\n=== Run plan ===")
    print(header)
    print("-" * len(header))
    keys = sorted({k[:4] for k in counts})
    for model, system, variant, suite in keys:
        b = counts.get((model, system, variant, suite, "benign"), 0)
        a = counts.get((model, system, variant, suite, "attack"), 0)
        print(f"{model:<16}{system:<11}{variant:<10}{suite:<11}{b:>7}{a:>7}")
    print("-" * len(header))
    cost, basis = estimate_cost(to_run, models, logdir)
    print(f"To run : {len(to_run)} task evaluations ({len(cached)} cached, skipped)")
    print(f"Cost   : ~${cost:,.0f}  [{basis}]")
    print(f"Wall   : ~{-(-len(to_run) // max_workers)} task-times at --max-workers={max_workers} "
          f"(10 min budget/task)\n")
