Installation
------------
Install `llm`:
```
pip install llm
```
Add your openai key:
```
# Paste your OpenAI API key into this
llm keys set openai
```

Build and run
-------------
```
make run <target>
```
e.g. `make run files-agent`. The `build` step runs
`cabal build --write-ghc-environment-files=always all`, which writes a
`.ghc.environment.*` file at the repo root so `hint` can load the project's
packages at runtime.

AgentDojo experiments
---------------------
One command runs the full evaluation (TypeGuard + CaMeL, all suites, benign
and under attack) and emits the raw data dump plus the paper's LaTeX tables:
```
python eval/run.py --models eval/configs/*.json
```
See [eval/README.md](eval/README.md) for outputs, options (`--suites`,
`--attacks`, `--plan-only`, ...), and how to add models.
