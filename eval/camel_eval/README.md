# CaMeL baseline

The CaMeL comparison runs from a patched clone of
[google-research/camel-prompt-injection](https://github.com/google-research/camel-prompt-injection)
at `<repo>/camel` (gitignored). Everything is driven by `eval/run.py`:
`execute.ensure_camel_checkout` clones and patches automatically, and each
CaMeL task evaluation runs as

```bash
uv run --project camel --env-file camel/.env \
    python eval/camel_eval/worker.py '<atom json>'
```

so CaMeL's own pinned dependencies are used. The worker builds the pipeline
with CaMeL's (patched) `make_tools_pipeline` and writes results in the
standard AgentDojo layout, so `process.py` treats both systems uniformly.

## What changes.patch changes

- **`main.py`** — adds `--attack-name` and `--no-policy` flags (upstream
  hardcodes `important_instructions` and the no-policy engine).
- **`src/camel/models.py`** —
  - registers `gpt-5.4-2026-03-05` as a reasoning model, recognizes the
    `gpt-5` family in `_is_oai_reasoning_model`;
  - `CAMEL_EXTRA_MODELS` / `CAMEL_EXTRA_REASONING_MODELS` env hooks to
    register further models without editing the file;
  - a `no_policy` parameter on `make_tools_pipeline`: off (our default) wires
    in the suite's security engine with `max_attempts=1`; on uses
    `ADNoSecurityPolicyEngine` with a `+camel-nopolicy` pipeline-name suffix
    so the two variants' result caches don't collide.
- **`src/camel/pipeline_elements/privileged_llm.py`** — catches
  `SecurityPolicyDeniedError` and routes it through `CaMeLException` so a
  policy denial fails the task cleanly instead of crashing the benchmark.

## Regenerating the patch after upstream changes

```bash
git -C camel diff main.py src/camel/models.py \
    src/camel/pipeline_elements/privileged_llm.py > eval/camel_eval/changes.patch
```
