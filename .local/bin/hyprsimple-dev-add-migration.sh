#!/bin/bash

# Create a new migration whose name sorts after every existing one.
#
#   hyprsimple-dev-add-migration.sh [--no-edit]
#
# Run this from a hyprsimple checkout.
#
# The name is a unix timestamp, because hyprsimple-migrate.sh runs migrations in
# the order the shell globs them, which for digits is numeric order. So the name
# decides the order they run in on every machine.
#
# It used to be the last commit's timestamp alone, on the stated claim that this
# sorts after everything already there. That does not hold. A migration added by
# hand carries whatever number was typed, and 1788644900 sat about six hours
# ahead of every commit date in the repository, so the next migration this tool
# named would have sorted before it and run first.
#
# Taking the later of the last commit and the highest existing name keeps the
# claim true whatever is already in migrations/.

set -e

repo_root=$(git rev-parse --show-toplevel)

stamp=$(git -C "$repo_root" log -1 --format=%cd --date=unix)

newest=0
for existing in "$repo_root/migrations"/*.sh; do
  [[ -f $existing ]] || continue
  name=$(basename "$existing" .sh)
  # Anything not a plain number cannot be compared, and cannot be sorted after
  # either. Skipped rather than guessed at.
  [[ $name =~ ^[0-9]+$ ]] || continue
  (( name > newest )) && newest=$name
done

(( newest >= stamp )) && stamp=$((newest + 1))

migration_file="$repo_root/migrations/$stamp.sh"

# There is no "already exists" guard here any more. It used to be needed,
# because two migrations written against the same commit were given the same
# name and the second would have overwritten the first. With the name taken
# past the highest existing one, the chosen name is by construction one nobody
# holds, so the guard could not fire and running twice in a row now works.

cat >"$migration_file" <<'TEMPLATE'
echo "Describe what this migration does"

TEMPLATE

if [[ $1 != "--no-edit" ]]; then
  "${EDITOR:-nvim}" "$migration_file"
fi

echo "$migration_file"
