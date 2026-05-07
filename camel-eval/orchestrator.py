#!/usr/bin/env python3
"""Orchestrate baseline + 2 CaMeL attack runs with a per-task 10-min budget."""

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CAMEL = str(ROOT / "camel")
LOGS = str(ROOT / "logs")
UV = shutil.which("uv") or os.path.expanduser("~/.local/bin/uv")
PIPELINE = "gpt-5.4-2026-03-05-high+camel"
SUITE = "slack"
NUM_USER_TASKS = 21
NUM_INJECTION_TASKS = 5
TASK_BUDGET_S = 600
POLL_S = 30


def base_dir() -> str:
    return f"{CAMEL}/logs/{PIPELINE}/{SUITE}"


def expected_jsons(attack_name: str) -> list[tuple[str, str, str]]:
    if attack_name == "none":
        return [
            (f"user_task_{i}", "none", f"{base_dir()}/user_task_{i}/none/none.json")
            for i in range(NUM_USER_TASKS)
        ]
    return [
        (
            f"user_task_{i}",
            f"injection_task_{j}",
            f"{base_dir()}/user_task_{i}/{attack_name}/injection_task_{j}.json",
        )
        for i in range(NUM_USER_TASKS)
        for j in range(1, NUM_INJECTION_TASKS + 1)
    ]


def is_finalized(p: str) -> bool:
    try:
        d = json.load(open(p))
    except Exception:
        return False
    return d.get("utility") in (True, False)


def task_age_s(p: str) -> float | None:
    """Seconds since the JSON's evaluation_timestamp, or None if no JSON."""
    try:
        d = json.load(open(p))
        ts_str = d.get("evaluation_timestamp")
        if not ts_str:
            return None
        t = time.mktime(time.strptime(ts_str, "%Y-%m-%d %H:%M:%S"))
        return time.time() - t
    except Exception:
        return None


def mark_failed(p: str, reason: str) -> None:
    Path(os.path.dirname(p)).mkdir(parents=True, exist_ok=True)
    if os.path.exists(p):
        try:
            d = json.load(open(p))
        except Exception:
            d = {}
    else:
        d = {}
    parts = p.split("/")
    user_task_id = "?"
    if "/user_task_" in p:
        user_task_id = "user_task_" + p.split("/user_task_")[1].split("/")[0]
    attack_dir = parts[-2] if len(parts) >= 2 else "none"
    fname = parts[-1].replace(".json", "")
    attack_type = None if attack_dir == "none" else attack_dir
    injection_task_id = None if fname == "none" else fname
    base = {
        "suite_name": SUITE,
        "pipeline_name": PIPELINE,
        "user_task_id": user_task_id,
        "injection_task_id": injection_task_id,
        "attack_type": attack_type,
        "injections": {},
        "messages": [],
        "benchmark_version": None,
        "evaluation_timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "agentdojo_package_version": "0.1.34",
    }
    base.update(d)
    base["utility"] = False
    base["security"] = True
    base["error"] = reason
    base["duration"] = float(TASK_BUDGET_S)
    if len(base.get("messages") or []) < 2:
        base["messages"] = [
            {"role": "system", "content": [{"type": "text", "content": ""}]},
            {"role": "user", "content": [{"type": "text", "content": ""}]},
        ]
    json.dump(base, open(p, "w"))


def find_overbudget_task(expected: list[tuple[str, str, str]]) -> str | None:
    for _, _, p in expected:
        if is_finalized(p):
            continue
        age = task_age_s(p)
        if age is not None and age > TASK_BUDGET_S:
            return p
    return None


def ensure_run_complete(attack_name: str, stdout_log: str) -> dict:
    expected = expected_jsons(attack_name)
    log(f"=== ensure {attack_name} complete: {len(expected)} expected evaluations ===")
    iteration = 0
    while True:
        finalized = sum(1 for _, _, p in expected if is_finalized(p))
        log(f"[{attack_name}] finalized {finalized}/{len(expected)}")
        if finalized >= len(expected):
            log(f"[{attack_name}] all done")
            break
        iteration += 1
        if iteration > 60:
            log(f"[{attack_name}] gave up after 60 restart iterations")
            break
        cmd = [
            UV, "run", "--project", CAMEL, "--env-file", f"{CAMEL}/.env",
            f"{CAMEL}/main.py",
            "openai:gpt-5.4-2026-03-05",
            "--reasoning-effort", "high",
            "--suites", "slack",
        ]
        if attack_name != "none":
            cmd += ["--run-attack", "--attack-name", attack_name]
        log(f"[{attack_name}] iter {iteration}: launching")
        with open(stdout_log, "ab") as f:
            f.write(f"\n\n===== iteration {iteration} starting at {time.strftime('%Y-%m-%d %H:%M:%S')} =====\n".encode())
            proc = subprocess.Popen(cmd, cwd=CAMEL, stdout=f, stderr=subprocess.STDOUT)
        last_count = finalized
        while proc.poll() is None:
            time.sleep(POLL_S)
            cur = sum(1 for _, _, p in expected if is_finalized(p))
            if cur > last_count:
                log(f"[{attack_name}] finalized {cur}/{len(expected)}")
                last_count = cur
            over = find_overbudget_task(expected)
            if over is not None:
                age = task_age_s(over)
                log(f"[{attack_name}] OVERBUDGET ({age:.0f}s): {over}; killing run, marking failed, restarting")
                proc.terminate()
                try:
                    proc.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    try:
                        proc.wait(timeout=5)
                    except subprocess.TimeoutExpired:
                        pass
                mark_failed(over, f"10min per-task budget exceeded during {attack_name} run")
                break
        else:
            pass
        if proc.poll() is not None and proc.returncode not in (0, None):
            log(f"[{attack_name}] child exit code {proc.returncode}")
        time.sleep(2)
    return aggregate(attack_name)


def aggregate(attack_name: str) -> dict:
    expected = expected_jsons(attack_name)
    n = 0
    up = 0
    sp = 0
    durs: list[float] = []
    for _, _, p in expected:
        if is_finalized(p):
            d = json.load(open(p))
            n += 1
            if d.get("utility"):
                up += 1
            if d.get("security"):
                sp += 1
            durs.append(float(d.get("duration") or 0))
    return {
        "n": n,
        "total": len(expected),
        "utility_pass": up,
        "security_pass": sp,
        "avg_duration_s": (sum(durs) / len(durs)) if durs else 0,
    }


def log(msg: str) -> None:
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(f"{LOGS}/camel-orchestrator.log", "a") as f:
        f.write(line + "\n")


def write_summary(rows: list[tuple[str, dict]]) -> None:
    out = f"{LOGS}/camel-summary.txt"
    with open(out, "w") as f:
        f.write("CaMeL slack suite, gpt-5.4 high reasoning, max_attempts=1, SlackSecurityPolicyEngine\n")
        f.write(f"Per-task 10-min hard budget (failures forced to utility=False, security=True)\n\n")
        f.write(f"{'config':<26}{'finished':<14}{'utility':<22}{'security':<22}{'avg dur':<10}\n")
        for label, r in rows:
            ut = f"{r['utility_pass']}/{r['n']} = {r['utility_pass']/r['n']:.1%}" if r['n'] else "n/a"
            sc = f"{r['security_pass']}/{r['n']} = {r['security_pass']/r['n']:.1%}" if r['n'] else "n/a"
            f.write(f"{label:<26}{r['n']}/{r['total']:<12}{ut:<22}{sc:<22}{r['avg_duration_s']:.0f}s\n")
    log(f"summary written to {out}")


def main():
    log("orchestrator starting")
    baseline = ensure_run_complete("none", f"{LOGS}/camel-slack-secpol.stdout.log")
    log(f"baseline stats: {baseline}")
    imp = ensure_run_complete("important_instructions", f"{LOGS}/camel-slack-attack-important.stdout.log")
    log(f"important_instructions stats: {imp}")
    direct = ensure_run_complete("direct", f"{LOGS}/camel-slack-attack-direct.stdout.log")
    log(f"direct stats: {direct}")
    write_summary([
        ("baseline (no attack)", baseline),
        ("important_instructions", imp),
        ("direct", direct),
    ])
    log("orchestrator done")


if __name__ == "__main__":
    main()
