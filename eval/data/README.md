# Eval results

Scored AgentDojo `slack` results for the TypeGuard vs CaMeL comparison.

- `main/results/` — utility and security, k=1. `utility_slack.tex`,
  `security_slack.tex`, `confidence_intervals.tex`, and `dump.jsonl` with one
  row per scored cell.
- `adversarial/results/` — compromised subagent attack, TypeGuard only, k=7.
  `adversarial_slack.tex`, `confidence_intervals.tex`, and `dump.jsonl`.
- `model_versions.txt` — model snapshots and serving platforms for the run.

`dump.jsonl` is the machine readable source the tables are built from. Raw per
cell transcripts and recordings stay in the local gitignored archive.
