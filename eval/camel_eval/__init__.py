"""Self contained CaMeL baseline.

The checkout at <repo>/camel is a pristine clone of camel-prompt-injection.
The runner calls ensure_checkout and worker_cmd, and the worker module
builds pipelines inside the checkout's own venv.
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO_ROOT = HERE.parents[1]
CHECKOUT = REPO_ROOT / "camel"

REPO_URL = "https://github.com/google-research/camel-prompt-injection.git"


def ensure_checkout() -> Path:
    if not CHECKOUT.exists():
        print(f"[camel] cloning into {CHECKOUT}", flush=True)
        subprocess.run(["git", "clone", REPO_URL, str(CHECKOUT)], check=True)
    if subprocess.run(["git", "diff", "--quiet"], cwd=CHECKOUT).returncode:
        sys.exit("the camel checkout has local changes, it must stay pristine")
    env_file = CHECKOUT / ".env"
    if not env_file.exists():
        env_file.write_text("")
    if "OPENAI_API_KEY" not in env_file.read_text() and os.environ.get("OPENAI_API_KEY"):
        with env_file.open("a") as f:
            f.write(f'\nOPENAI_API_KEY="{os.environ["OPENAI_API_KEY"]}"\n')
    return CHECKOUT


def worker_cmd(spec: dict) -> list[str]:
    uv = shutil.which("uv") or os.path.expanduser("~/.local/bin/uv")
    return [uv, "run", "--project", str(CHECKOUT), "--env-file", str(CHECKOUT / ".env"),
            "python", str(HERE.parent / "run.py"), "worker", json.dumps(spec)]
