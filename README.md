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
To run the experiments and produce the result tables (see
[eval/README.md](eval/README.md) for options):
```
python eval/run.py --models eval/configs/*.json
```
