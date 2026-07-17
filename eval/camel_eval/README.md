# CaMeL baseline

The CaMeL comparison runs from a pristine clone of
[google-research/camel-prompt-injection](https://github.com/google-research/camel-prompt-injection)
at `<repo>/camel` (gitignored, cloned automatically, asserted unmodified).
Each CaMeL benchmark runs `eval/run.py worker` inside the checkout's own
venv (`uv run --project camel`), so CaMeL's pinned dependencies are used
and no CaMeL source is changed.

Both variants follow upstream's published methodology and names:

- **`+camel`** (our no policy variant) — upstream's fresh pass:
  `make_tools_pipeline` as shipped, which wires the no policy engine.
- **`+camel+secpol`** (our policy variant) — upstream's
  `PrivilegedLLMReplayer`: it replays the recorded `+camel` run of the same
  task under the suite's security policy engine, replaying even the
  quarantined LLM responses, so it costs no LLM calls. The runner therefore
  schedules `+camel+secpol` after `+camel`.

Upstream writes its results under its own `+camel` / `+camel+secpol`
pipeline names. The worker copies each result to our uniform
`camel-<variant>-<model>` location, leaving the recording in place for the
replayer, so the rest of the eval never needs to know CaMeL's naming.

The only accommodations, both in `worker.py` and zero lines of CaMeL diff:
`_is_oai_reasoning_model` is extended to recognize the `gpt-5` family, and
the replayer's `logs/` recording root is provided as a symlink to the run's
rep directory.
