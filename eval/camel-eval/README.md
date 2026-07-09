# CaMeL slack-suite evaluation

Reproduces the CaMeL numbers we use as a comparison baseline: AgentDojo's slack
suite under `gpt-5.4` (high reasoning), `max_attempts=1`, and the slack policy
engine wired into the live PrivilegedLLM, with a per-task 10-minute hard
budget.

## Setup

From the repo root:

```bash
bash eval/camel-eval/setup.sh         # clones camel/, applies our-changes.patch
```

Then put your OpenAI key in `camel/.env` (`OPENAI_API_KEY="sk-..."`).

`uv` is required ([install](https://docs.astral.sh/uv/getting-started/installation/)).
Dependencies are installed automatically on first `uv run`.

## Run

**With-policy baseline + both attacks** (long: ~6–8 hours total):

```bash
python3 eval/camel-eval/orchestrator.py
```

Runs three phases sequentially against `slack`: baseline (no attack), then
`--run-attack --attack-name important_instructions`, then `--attack-name
direct`. Per-task watchdog kills any single (user_task × injection_task) eval
that exceeds 10 minutes; the killed eval is recorded with `utility=False,
security=True` so the suite resumes from cache. Final aggregate at
`logs/camel-summary.txt`.

**No-policy baseline** (after the with-policy run finishes):

```bash
bash eval/camel-eval/nopolicy-runner.sh
```

Waits for the with-policy summary, then patches `models.py` to use
`ADNoSecurityPolicyEngine` (with a `+camel-nopolicy` pipeline-name suffix so
the cache doesn't collide), reruns the slack baseline, appends a row to
`logs/camel-summary.txt`, and restores `models.py` afterward.

## Outputs

- `logs/camel-summary.txt` — final aggregate.
- `logs/camel-orchestrator.log`, `logs/camel-nopolicy-orchestrator.log` —
  per-iteration progress.
- `logs/camel-slack-{secpol,attack-important,attack-direct}.stdout.log`,
  `logs/camel-nopolicy.stdout.log` — raw camel stdout.
- `camel/logs/<pipeline-name>/slack/user_task_<i>/<attack>/<inj>.json` —
  per-evaluation traces (model output, tool calls, utility, security, duration).

## What the patch changes

`eval/camel-eval/our-changes.patch` modifies upstream camel/ in three files:

- `main.py`: adds `--attack-name` CLI flag (upstream hardcodes
  `important_instructions`).
- `src/camel/models.py`: registers `gpt-5.4-2026-03-05` as a reasoning model;
  recognizes `gpt-5` family in `_is_oai_reasoning_model`; default branch passes
  the suite-specific `engine` (instead of `ADNoSecurityPolicyEngine`) and
  `max_attempts=1` to `PrivilegedLLM`.
- `src/camel/pipeline_elements/privileged_llm.py`: catches
  `SecurityPolicyDeniedError` in `run_code` and routes it through
  `CaMeLException` so a denial fails the task cleanly instead of crashing the
  benchmark.
