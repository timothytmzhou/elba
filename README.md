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
e.g. `make run filesAgent`. The `build` step runs
`cabal build --write-ghc-environment-files=always all`, which writes a
`.ghc.environment.*` file at the repo root so `hint` can load the project's
packages at runtime.
