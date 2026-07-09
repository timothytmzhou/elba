#!/bin/bash
# Set up the CaMeL clone with our patches applied. Run from the repo root or
# from camel-eval/. Idempotent: skips clone/patch if already done.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
CAMEL="$ROOT/camel"
PATCH="$SCRIPT_DIR/our-changes.patch"

if [ ! -d "$CAMEL" ]; then
    echo "[setup] cloning camel-prompt-injection into $CAMEL"
    git clone https://github.com/google-research/camel-prompt-injection.git "$CAMEL"
else
    echo "[setup] $CAMEL already exists, skipping clone"
fi

cd "$CAMEL"

if git diff --quiet -- main.py src/camel/models.py src/camel/pipeline_elements/privileged_llm.py; then
    echo "[setup] applying patch"
    git apply --3way "$PATCH"
else
    echo "[setup] camel/ already has local modifications; skipping patch (apply manually if needed: git apply $PATCH)"
fi

if [ ! -f "$CAMEL/.env" ]; then
    cp "$CAMEL/.env.example" "$CAMEL/.env"
    echo "[setup] created $CAMEL/.env from example — fill in OPENAI_API_KEY before running"
else
    echo "[setup] $CAMEL/.env already exists"
fi

if ! command -v uv >/dev/null 2>&1 && ! [ -x "$HOME/.local/bin/uv" ]; then
    echo "[setup] uv not found — install via https://docs.astral.sh/uv/getting-started/installation/"
fi

echo "[setup] done"
