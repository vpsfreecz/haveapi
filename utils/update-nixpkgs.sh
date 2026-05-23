#!/bin/sh -eu

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1" >&2
    exit 1
  fi
}

short_rev() {
  jq -r '.nodes.nixpkgs.locked.rev' flake.lock | cut -c1-11
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

old_rev=$(short_rev)

nix flake update nixpkgs

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

printf 'flake: nixpkgs %s -> %s\n' "$old_rev" "$new_rev" > "$msg_file"
git commit -F "$msg_file"
