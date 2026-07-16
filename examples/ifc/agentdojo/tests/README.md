# Reference and opacity tests for the slack suite

No LLM involved. Two kinds of check:

- **Reference tests** (`run_tests.py`) — one hand-coded program per
  AgentDojo user task, run against AgentDojo's real slack environment
  through the bridge protocol and judged with each task's own
  `utility(...)`. [`Reference.hs`](Reference.hs) implements every task in
  plain `IO` (all 21 must pass). [`SecureReference.hs`](SecureReference.hs)
  implements them in `DC` against the labeled `Slack`/`Web` surface; tasks
  whose necessary flows the IFC policy forbids finish as
  `blocked by IFC (expected)`.
- **Opacity test** (`test_opacity.sh`) — feeds snippets to the secure slack
  binary as if the model had emitted them and asserts the typechecker
  rejects everything outside the sanctioned surface (TCB primitives, the
  `LIOTCB` constructor, lio's own API, host-side entry points) while benign
  code and real tool calls run.

## Running

```sh
cabal build agentdojo-slack-reference agentdojo-slack-secure-reference
python run_tests.py                     # all reference tests
python run_tests.py secref-user_task_5  # one

cabal build agentdojo-slack-secure
bash test_opacity.sh
```
