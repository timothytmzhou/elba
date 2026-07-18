# CaMeL baseline

The CaMeL comparison runs from a pristine clone of
[camel-prompt-injection](https://github.com/google-research/camel-prompt-injection)
at `<repo>/camel` inside its own `uv` venv, with zero source changes.
`camel-nopolicy` is upstream's fresh pass and `camel-policy` is upstream's
`PrivilegedLLMReplayer` replaying that recording under the suite's policy
engine at no LLM cost, with each result copied to our uniform result path.
