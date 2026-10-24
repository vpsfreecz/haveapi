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

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

if ! git diff --quiet -- flake.lock || ! git diff --cached --quiet -- flake.lock; then
  echo "error: flake.lock has uncommitted changes" >&2
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

nix flake check

git add flake.lock

if git diff --cached --quiet -- flake.lock; then
  echo "flake.lock did not change"
  exit 0
fi

msg_file=$(mktemp)
trap 'rm -f "$msg_file"' EXIT

printf 'flake: nixpkgs %.11s -> %.11s\n' "$old_rev" "$new_rev" > "$msg_file"
git commit -F "$msg_file"
