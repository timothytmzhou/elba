# AgentDojo evaluation

One command runs TypeGuard and CaMeL, with/without IFC policies, benign and under attack, and produces the paper outputs:
```bash
python eval/run.py --models eval/configs/*.json
```
Prints the run plan, confirms (`--yes` to skip), runs everything in parallel, resumes from a result-file cache.

## Outputs (`<logdir>/results/`)
- `dump.jsonl` — raw per-task records (verdicts, duration, tokens, transcript paths)
- `table_<suite>.tex` — paste-ready paper table per suite
- `confidence_intervals.tex` — TypeGuard − CaMeL paired-difference 95% CIs (Newcombe)

## Structure
```
run.py         CLI plus run_benchmark / run_benchmarks
config.py      model config types and loader
benchmark.py   run matrix, result paths, the plan
result.py      per-task result type and loader
bridge.py      JSON protocol with the Haskell agent binary
process.py     dump.jsonl, Newcombe CIs, LaTeX tables
configs/       one JSON per model
camel_eval/    self-contained CaMeL baseline
tests/         pytest suite, no LLM calls
```

## The run matrix
Independent OS process per task evaluation, run in parallel.

| axis | values |
|---|---|
| system | `typeguard`, `camel` |
| variant | `policy`, `nopolicy` |
| suite | `slack` |
| attack | none, `direct`, `important_instructions` |
| repeats | `--repeats k` (default 1 = pass@1) |

Per-task budget is 10 minutes; a timeout scores as failure.

## Adding a model
Drop a JSON into `configs/`:
```json
{ "model": "openai:gpt-5.4", "reasoningEffort": "high", "seed": 0 }
```
`model` is `provider:api-id` (the pydantic-ai format): the id goes to the `llm` CLI and the full string to CaMeL, so use an id both accept (`llm` can register new ones via `extra-openai-models.yaml`). Providers CaMeL lacks run TypeGuard only. By default everything runs on provider API keys; adding a `bedrock_model` profile id lets `--bedrock` move that model onto Bedrock instead (an `llm` plugin on the TypeGuard side), authenticating through the AWS chain (EC2 instance role plus `AWS_REGION`). OpenAI models on Bedrock use its OpenAI compatible endpoint, which needs `AWS_BEARER_TOKEN_BEDROCK`. On the TypeGuard side install `llm-bedrock` plus `llm install -e eval/llm-bedrock-extra`, then list the profile ids in `LLM_BEDROCK_MODELS`.

## Prerequisites
GHC/cabal to build the binary; the `llm` CLI with provider credentials; `uv` for CaMeL.
