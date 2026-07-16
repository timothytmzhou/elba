"""Parallel launcher. Runs each atom as its own OS process.

Typeguard atoms run bridge.py. CaMeL atoms run camel_eval.worker inside the
CaMeL checkout. Each atom has a hard timeout enforced by killing its process
group and recording the conventional failure result.
"""

from __future__ import annotations

import json
import subprocess
import sys
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

import camel_eval
from bridge import kill_group
from experiment import Atom, EVAL_DIR, REPO_ROOT, is_finalized


def _target(atom: Atom) -> str:
    return f"agentdojo-{atom.suite}" + ("-secure" if atom.variant == "policy" else "")


def resolve_typeguard_exes(atoms: list[Atom], build: bool = True) -> dict[str, str]:
    targets = sorted({_target(a) for a in atoms if a.system == "typeguard"})
    if not targets:
        return {}
    if build:
        subprocess.run(["cabal", "build", "--write-ghc-environment-files=always", *targets],
                       cwd=REPO_ROOT, check=True)
    return {t: subprocess.check_output(["cabal", "list-bin", t], cwd=REPO_ROOT,
                                       text=True).strip().splitlines()[-1] for t in targets}


def _atom_spec(atom, model, logdir, benchmark_version, timeout_s, exes, config_paths) -> dict:
    spec = {
        "suite": atom.suite, "task_id": atom.task_id, "attack": atom.attack,
        "injection_task_id": atom.injection_task_id, "variant": atom.variant,
        "benchmark_version": benchmark_version, "logdir": str(logdir / f"rep{atom.rep}"),
        "pipeline_name": model.pipeline_name(atom.system, atom.variant), "timeout_s": timeout_s,
    }
    if atom.system == "typeguard":
        spec |= {"exe": exes[_target(atom)], "config_path": str(config_paths[atom.model]),
                 "attack_model_name": model.attack_model_name}
    else:
        spec |= {"camel_model": model.camel_model,
                 "reasoning_effort": model.agent_config.get("reasoningEffort")}
    return spec


def _worker_cmd(atom: Atom, spec: dict) -> list[str]:
    if atom.system == "typeguard":
        return [sys.executable, str(EVAL_DIR / "bridge.py"), json.dumps(spec)]
    return camel_eval.worker_cmd(spec)


def _write_timeout_result(path: Path, atom: Atom, spec: dict, reason: str) -> None:
    # utility False and security True is AgentDojo's convention for failures.
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps({
        "suite_name": atom.suite, "pipeline_name": spec["pipeline_name"],
        "user_task_id": atom.task_id,
        "injection_task_id": None if atom.benign else atom.injection_task_id,
        "attack_type": None if atom.benign else atom.attack,
        "injections": {}, "benchmark_version": spec["benchmark_version"],
        "evaluation_timestamp": time.strftime("%Y-%m-%d %H:%M:%S"),
        "utility": False, "security": True, "error": reason,
        "duration": float(spec["timeout_s"]),
        "messages": [{"role": "system", "content": [{"type": "text", "content": ""}]},
                     {"role": "user", "content": [{"type": "text", "content": ""}]}],
    }))


def _write_agent_configs(models, logdir) -> dict[str, Path]:
    paths = {}
    for model in models.values():
        p = logdir / ".configs" / f"{model.name}.json"
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(model.agent_config, indent=2))
        paths[model.name] = p
    return paths


def run_atoms(atoms, models, logdir, benchmark_version, timeout_s, max_workers,
              build: bool = True) -> dict:
    if any(a.system == "camel" for a in atoms):
        camel_eval.ensure_checkout()
    exes = resolve_typeguard_exes(atoms, build=build)
    config_paths = _write_agent_configs(models, logdir)

    done = {"completed": 0, "timeout": 0, "crashed": []}
    lock = threading.Lock()
    start = time.time()

    def run_one(atom: Atom) -> None:
        spec = _atom_spec(atom, models[atom.model], logdir, benchmark_version,
                          timeout_s, exes, config_paths)
        result_path = atom.result_path(logdir, models)
        slug = f"{spec['pipeline_name']}-{atom.rep}-{atom.suite}-{atom.task_id}-{atom.attack}-{atom.injection_task_id}"
        log = logdir / ".workers" / f"{slug}.log"
        log.parent.mkdir(parents=True, exist_ok=True)

        status = "crashed"
        for _ in range(2):  # one retry for a worker that dies without a result
            with log.open("ab") as lf:
                proc = subprocess.Popen(_worker_cmd(atom, spec), stdout=lf,
                                        stderr=subprocess.STDOUT, cwd=REPO_ROOT,
                                        start_new_session=True)
                try:
                    proc.wait(timeout=timeout_s + 120)
                except subprocess.TimeoutExpired:
                    kill_group(proc)
                    proc.wait(timeout=10)
                    _write_timeout_result(result_path, atom, spec,
                                          f"killed after {timeout_s}s budget")
                    status = "timeout"
                    break
            if is_finalized(result_path):
                status = "completed"
                break
        with lock:
            if status == "crashed":
                done["crashed"].append((atom, str(log)))
            else:
                done[status] += 1
            n = done["completed"] + done["timeout"] + len(done["crashed"])
            print(f"[{n}/{len(atoms)} {(time.time() - start) / 60:.1f}min] {status}: {slug}",
                  flush=True)

    with ThreadPoolExecutor(max_workers=max_workers) as pool:
        for f in as_completed([pool.submit(run_one, a) for a in atoms]):
            f.result()
    return done
