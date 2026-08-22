#!/bin/bash

# Run every migration that has not run on this machine yet.
#
# Migrations live in $HYPRSIMPLE_PATH/migrations and are named after a unix
# timestamp so they run in the order they were written. Each one that succeeds
# leaves a marker in ~/.local/state/hyprsimple/migrations so it never runs
# twice. Fresh installs get every marker pre-created by install.sh, so new
# users skip the whole history.

export HYPRSIMPLE_PATH="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}"

STATE_DIR="$HOME/.local/state/hyprsimple/migrations"
mkdir -p "$STATE_DIR/skipped"

shopt -s nullglob
migrations=("$HYPRSIMPLE_PATH/migrations"/*.sh)

if (( ${#migrations[@]} == 0 )); then
  exit 0
fi

for file in "${migrations[@]}"; do
  filename=$(basename "$file")

  [[ -f $STATE_DIR/$filename ]] && continue
  [[ -f $STATE_DIR/skipped/$filename ]] && continue

  echo -e "\033[0;32m\nRunning migration (${filename%.sh})\033[0m"

  if bash "$file"; then
    touch "$STATE_DIR/$filename"
  else
    echo -e "\033[0;31mMigration ${filename%.sh} failed.\033[0m"
    read -rp "Skip it and continue? (y/N) " answer
    if [[ $answer == [yY] ]]; then
      touch "$STATE_DIR/skipped/$filename"
    else
      exit 1
    fi
  fi
done
