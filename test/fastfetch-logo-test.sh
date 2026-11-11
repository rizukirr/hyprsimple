#!/bin/bash
# fastfetch shows Hypri, the mascot, from Hypri.png instead of an ASCII logo.
# New installs get it from the shipped config. Existing ones get it from a
# migration, which may only switch a config that is still exactly as shipped,
# since the file promises it is the user's.
#
# Every run of the migration is against a throwaway HOME, so the machine
# running this suite is never edited. The last shipped config and logo live in
# test/fixtures/fastfetch-ascii, because CI checks out no history to read
# them from.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SHIPPED="$REPO/.config/fastfetch"
OLD="$REPO/test/fixtures/fastfetch-ascii"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

MIGRATION=$(grep -l "Show Hypri as the fastfetch logo" "$REPO"/migrations/*.sh | head -1)

# --- what ships ------------------------------------------------------------------

check "the shipped config shows Hypri.png" "$(grep -c '"source": "~/.config/fastfetch/Hypri.png"' "$SHIPPED/config.jsonc")" "1"
check "and the picture ships beside it" "$([[ -s $SHIPPED/Hypri.png ]] && echo yes || echo no)" "yes"
check "the ASCII logo no longer ships" "$([[ -e $SHIPPED/ascii.txt ]] && echo yes || echo no)" "no"
check "the config still says it is yours" "$(head -2 "$SHIPPED/config.jsonc" | grep -c 'This file is yours')" "1"

if [[ -z $MIGRATION ]]; then
  fail "no migration switches the fastfetch logo"
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
pass "found the migration, $(basename "$MIGRATION")"
check "its first line says what it does" "$(head -1 "$MIGRATION")" 'echo "Show Hypri as the fastfetch logo"'
check "and its fixture is a version it knows was shipped" \
  "$(grep -c "  $(md5sum "$OLD/config.jsonc" | cut -d' ' -f1)" "$MIGRATION")" "1"

run() { HOME="$1" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/out" 2>&1; }
home_with() {
  local h="$TMP/$1"
  mkdir -p "$h/.config/fastfetch"
  cp "$OLD/config.jsonc" "$OLD/ascii.txt" "$h/.config/fastfetch/"
  printf '%s' "$h"
}

# --- an install that never touched fastfetch is switched ---------------------------

h=$(home_with untouched)
run "$h"
check "it succeeds" "$?" "0"
check "and replaces the config with the new one" \
  "$(cmp -s "$SHIPPED/config.jsonc" "$h/.config/fastfetch/config.jsonc" && echo same || echo different)" "same"
check "and adds the picture" \
  "$(cmp -s "$SHIPPED/Hypri.png" "$h/.config/fastfetch/Hypri.png" && echo same || echo different)" "same"
check "and removes the ASCII logo it replaces" "$([[ -e $h/.config/fastfetch/ascii.txt ]] && echo left || echo gone)" "gone"
check "without a backup of a file that held no edits" "$(find "$h/.config/fastfetch" -name '*.bak*' | wc -l | tr -d ' ')" "0"
check "or anything half copied" "$(find "$h/.config/fastfetch" -name '.*partial' | wc -l | tr -d ' ')" "0"

before=$(find "$h" -type f -exec md5sum {} + | sort)
run "$h"
check "running it again succeeds" "$?" "0"
check "and changes nothing" "$(find "$h" -type f -exec md5sum {} + | sort)" "$before"

# --- edits are kept --------------------------------------------------------------

h=$(home_with edited-config)
printf '\n// my own module\n' >>"$h/.config/fastfetch/config.jsonc"
cp "$h/.config/fastfetch/config.jsonc" "$TMP/edited-config.jsonc"
run "$h"
check "an edited config succeeds" "$?" "0"
check "and is left exactly as it was" \
  "$(cmp -s "$TMP/edited-config.jsonc" "$h/.config/fastfetch/config.jsonc" && echo same || echo different)" "same"
check "and so is the ASCII logo it points at" "$([[ -f $h/.config/fastfetch/ascii.txt ]] && echo kept || echo gone)" "kept"
check "while the picture is there to opt in to" "$([[ -f $h/.config/fastfetch/Hypri.png ]] && echo yes || echo no)" "yes"
check "and it says how" "$(grep -c 'hyprsimple-refresh-config.sh fastfetch/config.jsonc' "$TMP/out")" "1"

h=$(home_with edited-logo)
printf 'my own logo\n' >"$h/.config/fastfetch/ascii.txt"
run "$h"
check "a logo of your own keeps the config pointing at it" "$(grep -c 'ascii.txt' "$h/.config/fastfetch/config.jsonc")" "1"
check "and the logo itself" "$(cat "$h/.config/fastfetch/ascii.txt")" "my own logo"

# --- nothing to do -----------------------------------------------------------------

h="$TMP/new"
mkdir -p "$h/.config/fastfetch"
cp "$SHIPPED/config.jsonc" "$SHIPPED/Hypri.png" "$h/.config/fastfetch/"
before=$(find "$h" -type f -exec md5sum {} + | sort)
run "$h"
check "an install that already shows Hypri succeeds" "$?" "0"
check "and is left alone" "$(find "$h" -type f -exec md5sum {} + | sort)" "$before"

h="$TMP/bare"
mkdir -p "$h"
run "$h"
check "a home with no fastfetch config succeeds" "$?" "0"
check "and is given none" "$([[ -e $h/.config/fastfetch ]] && echo created || echo absent)" "absent"

h=$(home_with old-install)
mkdir -p "$TMP/oldrepo/.config/fastfetch"
HOME="$h" HYPRSIMPLE_PATH="$TMP/oldrepo" bash "$MIGRATION" >"$TMP/out" 2>&1
check "an install that does not ship the picture succeeds" "$?" "0"
check "and changes nothing" \
  "$(cmp -s "$OLD/config.jsonc" "$h/.config/fastfetch/config.jsonc" && echo same || echo different)" "same"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
