# IFC tests for the secure slack/web wrapper

These tests exercise the `Slack`/`Web`/`ToLabeled` modules against
AgentDojo's slack environment without involving the LLM agent. Each
test is one DC computation that either:

- **`pass-*`** — completes without a label error (legitimate flow,
  analogous to AgentDojo user tasks).
- **`fail-*`** — is blocked by a label error (attack flow,
  analogous to AgentDojo injection tasks).

The test binary [`Tests.hs`](Tests.hs) dispatches by test name. The
Python driver [`run_tests.py`](run_tests.py) loads AgentDojo's slack
environment, spawns the binary once per test, and serves bridge
calls.

## Tests

### Pass

| name | description |
|---|---|
| `pass-simple-send` | Construct a labeled body and send a DM. |
| `pass-forward-labeled` | Read Alice's inbox and forward a message to Bob via `lFmap` (no `unlabel`). |
| `pass-tolabeled-web-slack` | Use `toLabeled` to scope a `getWebpage` call, then send the result to a slack DM. |
| `pass-tolabeled-web-web` | Use `toLabeled` to scope a `getWebpage` call, then `postWebpage`. |

### Fail

| name | description | what gets blocked |
|---|---|---|
| `fail-unlabel-then-send` | Read slack, unlabel, send DM. | Compromised reasoning (slack-integrity in current) writing to slack. |
| `fail-web-read-then-slack` | Inline `getWebpage`, then send DM. | Compromised reasoning (web-integrity) writing to slack. |
| `fail-unlabel-slack-post-web` | Read slack, unlabel, post to web. | Slack-secrecy current writing to public sink. |
| `fail-web-read-then-post` | Inline `getWebpage`, then `postWebpage`. | Same shape as above for two web ops without `toLabeled`. |

## Running

```sh
cabal build slack-tests
python run_tests.py                          # all tests
python run_tests.py pass-simple-send         # one
python run_tests.py --exe /path/to/binary    # override binary
```
