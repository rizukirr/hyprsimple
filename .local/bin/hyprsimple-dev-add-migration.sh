#!/bin/bash

# Create a new migration named after the unix timestamp of the last commit, so
# it sorts after every existing migration but before anything written later.
#
#   hyprsimple-dev-add-migration.sh [--no-edit]
#
# Run this from a hyprsimple checkout.

set -e

repo_root=$(git rev-parse --show-toplevel)
migration_file="$repo_root/migrations/$(git -C "$repo_root" log -1 --format=%cd --date=unix).sh"

if [[ -f $migration_file ]]; then
  echo "Migration already exists: $migration_file" >&2
  echo "Commit your current work first, then run this again." >&2
  exit 1
fi

cat >"$migration_file" <<'TEMPLATE'
echo "Describe what this migration does"

TEMPLATE

if [[ $1 != "--no-edit" ]]; then
  "${EDITOR:-nvim}" "$migration_file"
fi

echo "$migration_file"
