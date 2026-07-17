# CaMeL baseline

The CaMeL comparison runs from a patched clone of
[google-research/camel-prompt-injection](https://github.com/google-research/camel-prompt-injection)
at `<repo>/camel` (gitignored). Everything is driven by `eval/run.py`:
`camel_eval.ensure_checkout` clones and applies `camel.diff` automatically,
and each CaMeL task evaluation runs as

```bash
uv run --project camel --env-file camel/.env \
    python eval/camel_eval/worker.py '<atom json>'
```

so CaMeL's own pinned dependencies are used. The worker builds the pipeline
with CaMeL's (patched) `make_tools_pipeline` and writes results in the
standard AgentDojo layout, so `process.py` treats both systems uniformly.

## What camel.diff changes

A plain git diff, kept minimal.

- **`src/camel/models.py`** — registers `gpt-5.4-2026-03-05` as a
  reasoning model and recognizes the `gpt-5` family; adds a `no_policy`
  flag to `make_tools_pipeline` that swaps in `ADNoSecurityPolicyEngine`
  and suffixes the pipeline name `+camel-nopolicy` so the two variants'
  result caches don't collide.
- **`src/camel/pipeline_elements/privileged_llm.py`** — catches
  `SecurityPolicyDeniedError` and routes it through `CaMeLException` so a
  policy denial fails the task cleanly instead of crashing the benchmark.

## Regenerating after upstream changes

```bash
git -C camel diff src/camel/models.py \
    src/camel/pipeline_elements/privileged_llm.py > eval/camel_eval/camel.diff
```
