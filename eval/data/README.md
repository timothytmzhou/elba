# Eval results

Scored AgentDojo `slack` results for the TypeGuard vs CaMeL comparison.

- `main/rep1/` and `adversarial/rep1..rep7/` — one recording per run, holding the
  messages and tool calls that `eval/check_injections.py` replays.
- `main/results/` — utility and security, k=1. `utility_slack.tex`,
  `security_slack.tex`, `confidence_intervals.tex`, and `dump.jsonl` with one row
  per scored run.
- `adversarial/results/` — compromised subagent attack, TypeGuard only, k=7.
  `adversarial_slack.tex`, `confidence_intervals.tex`, and `dump.jsonl`.
- `model_versions.txt` — model snapshots and serving platforms for the run.

`dump.jsonl` is the machine readable source the tables are built from. The worker
stdout logs and the TypeGuard agent transcripts are too large to include here.
