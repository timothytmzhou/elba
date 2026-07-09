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

AgentDojo slack experiments
---------------------------
Run the AgentDojo slack benchmark against the IFC-secured agent:
```
# No-injection baseline (21 tasks):
python eval/run_eval.py \
  --exe $(cabal list-bin agentdojo-slack-secure) \
  --config examples/ifc/configs/gpt5.4-high.json \
  --logdir logs/eval-noattack

# Under attack (105 = 21 user_tasks * 5 injection_tasks):
python eval/run_eval.py \
  --exe $(cabal list-bin agentdojo-slack-secure) \
  --config examples/ifc/configs/gpt5.4-high.json \
  --attack important_instructions \
  --logdir logs/eval-important_instructions
```
Swap `agentdojo-slack-secure` for `agentdojo-slack-insecure` to run the
no-policy baseline. Other configs in `examples/ifc/configs/` switch the model.
Pass `--user-task user_task_N` to limit to a single task.
