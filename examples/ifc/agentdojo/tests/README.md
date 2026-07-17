# Reference tests for the slack suite

No LLM involved. One hand-coded program per AgentDojo user task, run
against AgentDojo's real slack environment through the bridge protocol and
judged with each task's own `utility(...)`.
[`Reference.hs`](Reference.hs) implements every task in plain `IO` (all 21
must pass). [`SecureReference.hs`](SecureReference.hs) implements them in
`DC` against the labeled `Slack`/`Web` surface; tasks whose necessary flows
the IFC policy forbids finish as `blocked by IFC (expected)`.

## Running

```sh
cabal build agentdojo-slack-reference agentdojo-slack-secure-reference
python run_tests.py                     # all reference tests
python run_tests.py secref-user_task_5  # one
```
