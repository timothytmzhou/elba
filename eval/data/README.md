# Eval results

Scored AgentDojo `slack` results for the TypeGuard vs CaMeL comparison.

- `main/` and `adversarial/rep1..rep7/` — one recording per run, holding the messages
  and tool calls that `eval/check_injections.py` replays.
- `main/results/` — utility and security. `utility_slack.tex`, `security_slack.tex`,
  `confidence_intervals.tex`, and `dump.jsonl` with one row per scored run.
- `adversarial/results/` — compromised subagent attack, TypeGuard only.
  `adversarial_slack.tex`, `confidence_intervals.tex`, and `dump.jsonl`.
- `model_versions.txt` — model snapshots and serving platforms for the run.

`dump.jsonl` is the machine readable source the tables are built from. The worker
stdout logs and the TypeGuard agent transcripts are too large to include here.

Re-derive the security verdicts from the recordings:

```bash
python eval/check_injections.py --recordings eval/data/main/camel-*
python eval/check_injections.py --recordings eval/data/main/typeguard-*
python eval/check_injections.py --recordings eval/data/adversarial/rep*/typeguard-nopolicy-*
python eval/check_injections.py --recordings eval/data/adversarial/rep*/typeguard-policy-*
```
