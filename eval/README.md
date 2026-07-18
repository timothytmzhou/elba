# AgentDojo evaluation

One command runs TypeGuard and CaMeL, with/without IFC policies, benign and under attack, and produces the paper outputs:
```bash
python eval/run.py --models eval/configs/*.json
```
Prints the run plan, confirms (`--yes` to skip), runs everything in parallel, resumes from a result-file cache.

## Outputs (`<logdir>/results/`)
- `dump.jsonl` — raw per-task records (verdicts, duration, tokens, transcript paths)
- `table_<suite>.tex` — paste-ready paper table per suite
- `confidence_intervals.tex` — TypeGuard − CaMeL paired-bootstrap 95% CIs

## Structure
```
run.py         CLI plus run_benchmark / run_benchmarks
config.py      model config types and loader
benchmark.py   run matrix, result paths, the plan
result.py      per-task result type and loader
bridge.py      JSON protocol with the Haskell agent binary
process.py     dump.jsonl, bootstrap CIs, LaTeX tables
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
{ "modelName": "gpt-5.4", "reasoningEffort": "high", "seed": 0, "camel_model": "openai:gpt-5.4-2026-03-05" }
```
One `AgentConfig` plus `camel_model`, named by its filename. Bedrock works via an `llm` plugin and a `bedrock:` camel_model, authenticating through the AWS chain (EC2 instance role plus `AWS_REGION`). No `camel_model` means TypeGuard only.

## Prerequisites
GHC/cabal to build the binary; the `llm` CLI with provider credentials; `uv` for CaMeL.
