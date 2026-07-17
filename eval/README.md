# AgentDojo evaluation

One command runs the full evaluation — TypeGuard and CaMeL, with and without
IFC policies, benign and under attack, all AgentDojo suites — and produces
the paper outputs:

```bash
python eval/run.py --models eval/configs/*.json
```

It first prints the plan (how many task evaluations will run, and a cost
estimate priced from [OpenAI's published rates](https://platform.openai.com/docs/pricing),
pinned in `pricing.json`), asks for confirmation (`--yes` to skip), runs every
remaining evaluation in parallel, then processes the results. Finished
evaluations are cached by result file, so rerunning resumes.

To reproduce the paper's slack-only tables:

```bash
python eval/run.py --models eval/configs/gpt5.4-high.json --suites slack
```

## Outputs (under `<logdir>/results/`)

- **`dump.jsonl`** — the raw data: one record per task evaluation with
  everything tracked — identity (system/variant/model/rep/suite/task/attack/
  injection), utility and security verdicts, duration, token usage (measured
  from the agent's `llm` logs), the agent's final output and full message
  log, error if any, and paths to the raw transcript and result file.
- **`table_<suite>.tex`** — the paste-ready paper table for each suite, in
  the format of Garby et al. (arXiv:2602.20064, Table 1): system x model
  rows; utility cells `n/N (p% ± hw)` with a clustered Student-t 95% CI over
  sampling units; security cells `n/N [lo, hi]` with a 95% Wilson score
  interval; per-attack columns.
- **`confidence_intervals.tex`** — TypeGuard − CaMeL paired-difference CIs
  per setting (Newcombe's score interval; the preprint's Table 3).

A plain-text summary of the same numbers is also printed to the terminal.

## Structure

Running and processing are separate; `run.py` chains them.

```
run.py         the small user-facing command (--plan-only / --process-only)
experiment.py  what to run: model configs, run matrix, plan + cost estimate
bridge.py      run one AgentDojo task through the Haskell agent binary
runner.py      launch every atom in parallel with per-task timeouts
process.py     data processing: dump.jsonl, statistics, LaTeX tables
pricing.json   OpenAI published prices for every model on the pricing page
configs/       one JSON per model — pass any subset via --models
camel_eval/    self-contained CaMeL baseline (checkout, patch, worker)
stub_agent.py  scripted fake agent; lets tests run the whole pipeline
tests/         pytest suite, no LLM calls:  python -m pytest eval/tests
```

Each suite's agent apps live in `examples/ifc/agentdojo/<suite>/app/`. An
app declares its tool modules in the `Env` and the agent sees every export
with its Haddock docstring in the prompt.

## The run matrix

Every task evaluation is independent ("embarrassingly parallel"): one OS
process per evaluation, `--max-workers` defaults to `ceil(n/4)` so a full
run takes about four sequential task-times. The per-task budget is 10
minutes (`--timeout`), as in the paper; timed-out tasks are recorded as
`utility=False, security=True` (AgentDojo's own convention for failures).

| axis    | values                                                            |
|---------|-------------------------------------------------------------------|
| system  | `typeguard` (ours), `camel`                                       |
| variant | `policy`, `nopolicy` — both run under attack (fills Table 2's gap) |
| suite   | `slack`, `workspace`, `travel`, `banking`                         |
| attack  | none + `direct`, `important_instructions`                         |
| repeats | `--repeats k` (default 1 = pass@1)                                 |

TypeGuard's `policy` variant only runs on suites whose IFC policies exist —
currently slack (`experiment.TYPEGUARD_POLICY_SUITES`). The other suites'
secure surfaces are `undefined` placeholders to be written by hand
(`examples/ifc/agentdojo/{workspace,travel,banking}/<Suite>.hs`); their
no-policy variants run everywhere. CaMeL ships policies for all four suites.

## Adding a model

Drop a JSON into `configs/`:

```json
{
  "name": "gpt-5.4-high",
  "display": "GPT-5.4 (high)",
  "camel_model": "openai:gpt-5.4-2026-03-05",
  "camel_reasoning": true,
  "agent_config": { "modelName": "gpt-5.4", "reasoningEffort": "high",
                    "seed": 0, "systemPrompt": "", "maxAttempts": 3, "maxDepth": 7 }
}
```

and add its price row to `pricing.json` if missing (the plan refuses to
guess). Models unknown to CaMeL get one registration line in
`camel_eval/camel.diff`.

## Prerequisites

- GHC/cabal (the runner builds the `agentdojo-<suite>` binaries itself);
  the `llm` CLI with a stored OpenAI key (`llm keys set openai`) or
  `OPENAI_API_KEY` in the environment. Each parallel agent gets a private
  `llm` state dir, which is also where token counts are measured from.
- For CaMeL: `uv`. The checkout (`<repo>/camel`, gitignored) is cloned and
  patched automatically on first use; `OPENAI_API_KEY` is written into
  `camel/.env`.
