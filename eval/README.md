# AgentDojo evaluation

## Reproducing the camera-ready tables

From the repository root:

```bash
python -m pip install -r eval/requirements-processing.txt
python eval/process.py
```

This reads the saved results in `eval/data/main` and `eval/data/adversarial` and regenerates their `results/` directories. It makes no model calls and does not require API keys or the Haskell binary. The default model configurations are Opus 4.7, Opus 4.8, GPT 5.4, and Sonnet 5 at high reasoning effort.

The main evaluation uses Newcombe's paired score intervals for Elba minus CaMeL task completion. The adversarial evaluation uses percentile bootstrap intervals over seven complete benchmark runs. Processing enumerates every resample and uses the 2.5th and 97.5th percentiles. These intervals describe variation between runs of the fixed benchmark. Unscored trials remain in the denominator and count as neither completed nor resisted. Policy enforcement intervals are marked N/A.

To check the results against the camera-ready tables:

```bash
python -m pip install pytest
python -m pytest eval/tests/test_process.py
```

## Running new experiments

One command runs Elba and CaMeL, with/without IFC policies, benign and under attack, and produces the paper outputs:
```bash
python eval/run.py --models eval/configs/*.json
```
Prints the run plan, confirms (`--no-confirm` to skip), runs everything in parallel, resumes from a result-file cache.

## Outputs (`<logdir>/results/`)
- `dump.jsonl` — one line per task evaluation: system, model, task, attack, and the utility/security verdicts (durations, tokens, and transcript paths stay in the per-task result JSONs under `<logdir>`)
- `utility_<suite>.tex`, `security_<suite>.tex`, `adversarial_<suite>.tex` — paste-ready paper tables
- `confidence_intervals.tex` — paired utility intervals for the main evaluation or utility and no-policy injection resistance intervals for the adversarial evaluation

## Checking the security verdicts
`check_injections.py` re-derives the verdicts from the recordings in `data/` rather than trusting the stored ones. It rebuilds the injected environment, replays each run's tool calls, and applies agentdojo's own security check:
```bash
python eval/check_injections.py
```
This diagnostic reports AgentDojo's raw verdicts on replayable traces. Its counts can differ from the paper tables because the tables include trials without replayable traces and the reviewed false-positive corrections described in the appendix.

## Structure
```
run.py               CLI plus run_benchmark / run_benchmarks
config.py            model config types and loader
benchmark.py         run matrix, result paths, the plan
result.py            per-task result type and loader
bridge.py            JSON protocol with the Haskell agent binary
process.py           saved result processing and camera-ready tables
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
| system | `elba`, `camel` |
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
`model` is `provider:api-id` (the pydantic-ai format): the id goes to the `llm` CLI and the full string to CaMeL, so use an id both accept (`llm` can register new ones via `extra-openai-models.yaml`). Providers CaMeL lacks run Elba only. By default everything runs on provider API keys; adding a `bedrock_model` profile id lets `--bedrock` move that model onto Bedrock instead (an `llm` plugin on the Elba side), authenticating through the AWS chain (EC2 instance role plus `AWS_REGION`). OpenAI models on Bedrock are Elba only, run CaMeL for them on their API key without the flag. On the Elba side install `llm-bedrock` plus `llm install -e eval/llm-bedrock-extra`, then list the profile ids in `LLM_BEDROCK_MODELS`.

## Prerequisites
GHC/cabal to build the binary; the `llm` CLI with provider credentials; `uv` for CaMeL.
