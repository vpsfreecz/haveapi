#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv sync --locked
uv run --locked python utils/run_ruff.py format --check .
uv run --locked python utils/run_ruff.py check .
uv run --locked mypy src
uv run --locked pytest tests/unit "$@"
