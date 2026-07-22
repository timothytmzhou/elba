# AgentDojo evaluation

One command runs TypeGuard and CaMeL, with/without IFC policies, benign and under attack, and produces the paper outputs:
```bash
python eval/run.py --models eval/configs/*.json
```
Prints the run plan, confirms (`--no-confirm` to skip), runs everything in parallel, resumes from a result-file cache.

## Outputs (`<logdir>/results/`)
- `dump.jsonl` — one line per task evaluation: system, model, task, attack, and the utility/security verdicts (durations, tokens, and transcript paths stay in the per-task result JSONs under `<logdir>`)
- `utility_<suite>.tex`, `security_<suite>.tex`, `adversarial_<suite>.tex` — paste-ready paper tables
- `confidence_intervals.tex` — TypeGuard − CaMeL paired-difference 95% CIs (Newcombe)

## Checking the security verdicts
`check_injections.py` re-derives the verdicts from the recordings in `data/` rather than trusting the stored ones. It rebuilds the injected environment, replays each run's tool calls, and applies agentdojo's own security check:
```bash
python eval/check_injections.py
```
```
                                    runs  violations
CaMeL main                          2375           0
TypeGuard main                      2520           0
TypeGuard adversarial (no policy)   2939         844
TypeGuard adversarial (policy)      2938          28
```

## Structure
```
run.py               CLI plus run_benchmark / run_benchmarks
config.py            model config types and loader
benchmark.py         run matrix, result paths, the plan
result.py            per-task result type and loader
bridge.py            JSON protocol with the Haskell agent binary
process.py           dump.jsonl, Newcombe CIs, LaTeX tables
check_injections.py  replays recordings through agentdojo's security check
configs/             one JSON per model
camel_eval/          self-contained CaMeL baseline
data/                committed recordings and the result tables
tests/               pytest suite, no LLM calls
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
`model` is `provider:api-id` (the pydantic-ai format): the id goes to the `llm` CLI and the full string to CaMeL, so use an id both accept (`llm` can register new ones via `extra-openai-models.yaml`). Providers CaMeL lacks run TypeGuard only. By default everything runs on provider API keys; adding a `bedrock_model` profile id lets `--bedrock` move that model onto Bedrock instead (an `llm` plugin on the TypeGuard side), authenticating through the AWS chain (EC2 instance role plus `AWS_REGION`). OpenAI models on Bedrock are TypeGuard only, run CaMeL for them on their API key without the flag. On the TypeGuard side install `llm-bedrock` plus `llm install -e eval/llm-bedrock-extra`, then list the profile ids in `LLM_BEDROCK_MODELS`.

## Prerequisites
GHC/cabal to build the binary; the `llm` CLI with provider credentials; `uv` for CaMeL.
