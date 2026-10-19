#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
uv sync --locked
uv run --locked python utils/run_ruff.py --config pyproject.toml format --check . ../../utils/release
uv run --locked python utils/run_ruff.py --config pyproject.toml check . ../../utils/release
uv run --locked mypy src
uv run --locked pytest tests/unit "$@"
