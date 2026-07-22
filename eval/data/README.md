# Eval results

Scored AgentDojo `slack` results for the Elba vs CaMeL comparison.

- `main/` and `adversarial/rep1..rep7/` — one recording per run, holding the messages
  and tool calls that `eval/check_injections.py` replays.
- `main/results/` — utility and security. `utility_slack.tex`, `security_slack.tex`,
  `confidence_intervals.tex`, and `dump.jsonl` with one row per scored run.
- `adversarial/results/` — compromised subagent attack, Elba only.
  `adversarial_slack.tex`, `confidence_intervals.tex`, and `dump.jsonl`.
- `model_versions.txt` — model snapshots and serving platforms for the run.

`dump.jsonl` is the machine readable source the tables are built from. The worker
stdout logs and the Elba agent transcripts are too large to include here.

Re-derive the security verdicts from the recordings (runs all four sweeps —
CaMeL main, Elba main, and the Elba adversarial variants — over `--data`,
which defaults to this directory):

```bash
python eval/check_injections.py
```
