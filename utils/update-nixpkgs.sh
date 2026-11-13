#!/bin/sh -eu

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1" >&2
    exit 1
  fi
}

short_rev() {
  nix shell "$CONFCTL_FLAKE" -c confctl inputs ls --json nixpkgs | jq -er '
    map(select(.input == "nixpkgs"))
    | if length == 1 then .[0].rev | select(type == "string" and length > 0) else empty end
  '
}

need_cmd git
need_cmd jq
need_cmd nix
need_cmd python3

if ! python3 -c 'import tomllib' 2>/dev/null; then
  echo "error: Python 3.11 or newer with tomllib is required" >&2
  exit 1
fi

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

ruff_project=clients/python/pyproject.toml
if ! git diff --quiet -- flake.lock "$ruff_project" ||
   ! git diff --cached --quiet -- flake.lock "$ruff_project"; then
  echo "error: flake.lock or $ruff_project has uncommitted changes" >&2
  exit 1
fi

if ! git diff --cached --quiet; then
  echo "error: staging area must be empty before updating nixpkgs" >&2
  exit 1
fi

: "${CONFCTL_FLAKE:?Set CONFCTL_FLAKE to the pinned confctl CI package}"

old_rev=$(short_rev)

nix shell "$CONFCTL_FLAKE" -c confctl inputs update --forward-only nixpkgs

new_rev=$(short_rev)

if [ "$old_rev" = "$new_rev" ]; then
  echo "nixpkgs is already up to date at $new_rev"
  exit 0
fi

ruff_version=$(nix eval --impure --raw --expr \
  '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem}.ruff.version')
python3 utils/sync-ruff.py "$ruff_version"

nix flake check

nix develop .#client-python -c bash <<'EOF'
set -euo pipefail
cd clients/python
uv sync
uv run --locked python utils/run_ruff.py format --check .
uv run --locked python utils/run_ruff.py check .
EOF

git add flake.lock "$ruff_project"

if git diff --cached --quiet -- flake.lock; then
  echo "flake.lock did not change"
  exit 0
fi

msg_file=$(mktemp)
trap 'rm -f "$msg_file"' EXIT

printf 'flake: nixpkgs %.11s -> %.11s\n' "$old_rev" "$new_rev" > "$msg_file"
git commit -F "$msg_file"
