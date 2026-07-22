# CaMeL baseline

`import camel` comes from a clone of Google's
[camel-prompt-injection](https://github.com/google-research/camel-prompt-injection)
at `<repo>/camel`, which is gitignored and must stay pristine.
`camel_eval.ensure_checkout` clones it on demand, or clone it by hand:

    git clone https://github.com/google-research/camel-prompt-injection.git camel

It is a `uv` project, so `import camel` resolves to `camel/src/camel` and the
worker runs in the clone's own venv, separate from the TypeGuard venv:

    uv run --project camel python eval/run.py worker ...

`camel-nopolicy` is upstream's fresh pass. `camel-policy` replays that recording
under the suite's security policies.
