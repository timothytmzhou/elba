#!/bin/bash
# Wait for the main orchestrator to drop the summary file, then:
#  1. Patch models.py: ADNoSecurityPolicyEngine + "+camel-nopolicy" pipeline name suffix
#  2. Run baseline slack with same params (max_attempts=1, gpt-5.4 high)
#  3. Aggregate results into the summary

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
LOGS="$ROOT/logs"
CAMEL="$ROOT/camel"
UV="${UV:-$(command -v uv || echo "$HOME/.local/bin/uv")}"
MODELS="$CAMEL/src/camel/models.py"
SUMMARY="$LOGS/camel-summary.txt"

echo "[$(date)] no-policy runner: waiting for $SUMMARY"
until [ -f "$SUMMARY" ]; do sleep 60; done
echo "[$(date)] no-policy runner: orchestrator summary appeared, starting no-policy run"

# Snapshot current models.py so we can restore
cp "$MODELS" "$MODELS.policy.bak"

# 1a) put ADNoSecurityPolicyEngine back into the default branch
MODELS_PATH="$MODELS" python3 - <<'PY'
import os, pathlib
p = pathlib.Path(os.environ["MODELS_PATH"])
src = p.read_text()
# Re-add import (was removed earlier)
src = src.replace(
    "from camel.pipeline_elements.security_policies import (\n    AgentDojoSecurityPolicyEngine,",
    "from camel.pipeline_elements.security_policies import (\n    ADNoSecurityPolicyEngine,\n    AgentDojoSecurityPolicyEngine,",
)
# Swap engine -> ADNoSecurityPolicyEngine in PrivilegedLLM call
src = src.replace(
    "PrivilegedLLM(\n                    llm,\n                    engine,\n                    q_llm or model,\n                    max_attempts=1,\n                ),",
    "PrivilegedLLM(\n                    llm,\n                    ADNoSecurityPolicyEngine,\n                    q_llm or model,\n                    max_attempts=1,\n                ),",
)
# Distinct pipeline name suffix so cache doesn't collide with the +secpol run
src = src.replace(
    'tools_pipeline.name = f"{model.split(\':\')[1]}-{reasoning_effort}+camel"\n        elif "anthropic" in model and (("3-7-sonnet" in model or "sonnet-4" in model) and thinking_budget_tokens):\n            tools_pipeline.name = f"{model.split(\':\')[1]}-{thinking_budget_tokens}+camel"\n        else:\n            tools_pipeline.name = f"{model.split(\':\')[1]}+camel"\n\n        if q_llm:',
    'tools_pipeline.name = f"{model.split(\':\')[1]}-{reasoning_effort}+camel-nopolicy"\n        elif "anthropic" in model and (("3-7-sonnet" in model or "sonnet-4" in model) and thinking_budget_tokens):\n            tools_pipeline.name = f"{model.split(\':\')[1]}-{thinking_budget_tokens}+camel-nopolicy"\n        else:\n            tools_pipeline.name = f"{model.split(\':\')[1]}+camel-nopolicy"\n\n        if q_llm:',
)
p.write_text(src)
print("models.py patched for no-policy run")
PY

python3 -m py_compile "$MODELS" || { echo "compile failed"; cp "$MODELS.policy.bak" "$MODELS"; exit 1; }

# 1b) launch the no-policy baseline using the same per-task-budget supervisor pattern
NEW_PIPELINE="gpt-5.4-2026-03-05-high+camel-nopolicy"
ORCH_LOG=$LOGS/camel-nopolicy-orchestrator.log
RUN_LOG=$LOGS/camel-nopolicy.stdout.log

python3 - <<PY
import json, os, subprocess, time
from pathlib import Path

CAMEL = "$CAMEL"
LOGS = "$LOGS"
UV = "$UV"
PIPELINE = "$NEW_PIPELINE"
SUITE = "slack"
NUM = 21
BUDGET = 600
POLL = 30
DIR = f"{CAMEL}/logs/{PIPELINE}/{SUITE}"

def expected():
    return [(f"user_task_{i}", f"{DIR}/user_task_{i}/none/none.json") for i in range(NUM)]

def is_finalized(p):
    try: d=json.load(open(p))
    except: return False
    return d.get("utility") in (True, False)

def task_age(p):
    try:
        d=json.load(open(p))
        ts=d.get("evaluation_timestamp")
        if not ts: return None
        return time.time() - time.mktime(time.strptime(ts, "%Y-%m-%d %H:%M:%S"))
    except: return None

def mark_failed(p, reason):
    Path(os.path.dirname(p)).mkdir(parents=True, exist_ok=True)
    try: d = json.load(open(p))
    except: d = {}
    base = {
        "suite_name": SUITE, "pipeline_name": PIPELINE,
        "user_task_id": "user_task_" + p.split("/user_task_")[1].split("/")[0],
        "injection_task_id": None, "attack_type": None, "injections": {},
        "messages": [], "benchmark_version": None,
        "evaluation_timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "agentdojo_package_version": "0.1.34",
    }
    base.update(d)
    base["utility"] = False; base["security"] = True
    base["error"] = reason; base["duration"] = float(BUDGET)
    if len(base.get("messages") or []) < 2:
        base["messages"] = [
            {"role":"system","content":[{"type":"text","content":""}]},
            {"role":"user","content":[{"type":"text","content":""}]},
        ]
    json.dump(base, open(p,"w"))

def log(m):
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {m}"
    print(line, flush=True)
    open("$ORCH_LOG","a").write(line+"\n")

log("no-policy run starting")
exp = expected()
it = 0
while True:
    fin = sum(1 for _,p in exp if is_finalized(p))
    log(f"finalized {fin}/{NUM}")
    if fin >= NUM: break
    it += 1
    if it > 30: log("giving up after 30 iterations"); break
    cmd = [UV,"run","--project",CAMEL,"--env-file",f"{CAMEL}/.env",
           f"{CAMEL}/main.py","openai:gpt-5.4-2026-03-05",
           "--reasoning-effort","high","--suites","slack"]
    log(f"iter {it}: launching")
    with open("$RUN_LOG","ab") as f:
        f.write(f"\n===== iter {it} at {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n".encode())
        proc = subprocess.Popen(cmd, cwd=CAMEL, stdout=f, stderr=subprocess.STDOUT)
    last = fin
    while proc.poll() is None:
        time.sleep(POLL)
        cur = sum(1 for _,p in exp if is_finalized(p))
        if cur > last: log(f"finalized {cur}/{NUM}"); last = cur
        over = None
        for _,p in exp:
            if is_finalized(p): continue
            a = task_age(p)
            if a is not None and a > BUDGET:
                over = p; break
        if over:
            log(f"OVERBUDGET ({task_age(over):.0f}s): {over}; killing + marking failed")
            proc.terminate()
            try: proc.wait(timeout=10)
            except subprocess.TimeoutExpired: proc.kill(); proc.wait(timeout=5)
            mark_failed(over, "10min per-task budget exceeded during no-policy run")
            break
    time.sleep(2)

# aggregate and append to camel-summary.txt
n=up=0
for _,p in exp:
    if not is_finalized(p): continue
    d = json.load(open(p))
    n += 1
    if d["utility"]: up += 1
log(f"no-policy final: {up}/{n} = {up/n:.1%}" if n else "no-policy: nothing finalized")

with open("$SUMMARY","a") as f:
    f.write(f"\nCaMeL (no policy)         {n}/{NUM}        {up}/{n} = {up/n:.1%}\n" if n else "\nCaMeL (no policy): no data\n")
log("appended to summary")
PY

# Restore models.py
cp "$MODELS.policy.bak" "$MODELS"
echo "[$(date)] no-policy runner: restored models.py"
