#!/bin/bash
# The installer's backup destroyed the thing it existed to protect.
#
#   backup_if_exists() {
#     if [ -e "$1" ] || [ -L "$1" ]; then
#       rm -rf "$1.backup"
#       mv "$1" "$1.backup"
#     fi
#   }
#
# The first install moves your own config to <target>.backup, which is the one
# copy of what was there before hyprsimple ever ran. A second install, run
# months later to repair something, deleted that and put hyprsimple's own
# previous copy there instead. Demonstrated on a fixture: after two installs
# the original was gone, zero copies left anywhere, and .backup held
# hyprsimple v1.
#
# The same lesson is already written into hyprsimple-muslimtify.sh's own backup
# function, which keeps the first rather than the most recent. install.sh is
# where it costs the most, and is where it had not been applied.
#
# Nothing here runs the installer. backup_if_exists is taken out of it and
# exercised against throwaway directories.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

fn=$(sed -n '/^backup_if_exists() {/,/^}/p' "$INSTALL")
if [[ $(printf '%s\n' "$fn" | grep -c .) -lt 10 ]]; then
  fail "extracted $(printf '%s\n' "$fn" | grep -c .) lines of backup_if_exists, so this is reading the wrong thing"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "extracted backup_if_exists from the installer"

# Runs the function with colours emptied.
backup() {
  bash -c "
    YELLOW=; NC=
    $fn
    backup_if_exists \"\$1\" \"\${2-}\"
  " _ "$@" >/dev/null 2>&1
}

DIR="$TMP/work"
reset() { rm -rf "${TMP:?}/work"; mkdir -p "$DIR"; }

# --- the case that lost the original ------------------------------------------

reset
mkdir -p "$DIR/waybar"
printf 'MY ORIGINAL\n' >"$DIR/waybar/config.jsonc"

# First install.
backup "$DIR/waybar"
mkdir -p "$DIR/waybar"; printf 'hyprsimple v1\n' >"$DIR/waybar/config.jsonc"
check "the first install backs the original up" \
  "$(cat "$DIR/waybar.backup/config.jsonc")" "MY ORIGINAL"

# Second install, months later.
backup "$DIR/waybar"
mkdir -p "$DIR/waybar"; printf 'hyprsimple v2\n' >"$DIR/waybar/config.jsonc"
check "and a second install leaves that backup alone" \
  "$(cat "$DIR/waybar.backup/config.jsonc")" "MY ORIGINAL"
check "so the original still exists somewhere" \
  "$(grep -rl 'MY ORIGINAL' "$DIR" 2>/dev/null | wc -l | tr -d ' ')" "1"
check "and the displaced copy is kept too, under a dated name" \
  "$(find "$DIR" -maxdepth 1 -name 'waybar.backup.*' | wc -l | tr -d ' ')" "1"
check "which holds what the second install displaced" \
  "$(cat "$DIR"/waybar.backup.*/config.jsonc)" "hyprsimple v1"

# --- nothing is backed up when nothing changed --------------------------------
#
# Without this, re-running the installer files a dated backup of hyprsimple's
# own unchanged scripts on every run.

reset
printf 'same\n' >"$DIR/script.sh"
printf 'same\n' >"$DIR/source.sh"
backup "$DIR/script.sh" "$DIR/source.sh"
check "an unchanged file is not backed up at all" \
  "$(find "$DIR" -name 'script.sh.backup*' | wc -l | tr -d ' ')" "0"
check "and is still there to be overwritten" \
  "$([[ -f $DIR/script.sh ]] && echo yes || echo no)" "yes"

printf 'different\n' >"$DIR/source.sh"
backup "$DIR/script.sh" "$DIR/source.sh"
check "a changed file is backed up" \
  "$(cat "$DIR/script.sh.backup")" "same"

# --- the shapes it has to handle ----------------------------------------------

reset
printf 'a file\n' >"$DIR/thing"
backup "$DIR/thing"
check "a plain file is moved aside" "$(cat "$DIR/thing.backup")" "a file"
check "and is gone from its old place" \
  "$([[ -e $DIR/thing ]] && echo present || echo moved)" "moved"

reset
ln -s /nonexistent "$DIR/thing"
backup "$DIR/thing"
check "a dangling symlink is moved aside, not skipped" \
  "$([[ -L $DIR/thing.backup ]] && echo yes || echo no)" "yes"

reset
backup "$DIR/absent"
check "something that is not there produces no backup" \
  "$(find "$DIR" -name 'absent*' | wc -l | tr -d ' ')" "0"

# --- nothing is ever destroyed ------------------------------------------------

check "the function no longer removes an existing backup" \
  "$(printf '%s\n' "$fn" | grep -c 'rm -rf')" "0"

# And every caller passes the source, so the unchanged case above is reachable
# from the installer rather than only from this suite.
check "every call site passes what it is about to write" \
  "$(grep -c 'backup_if_exists "\$target" "\$' "$INSTALL")" "3"
check "and none calls it with the target alone" \
  "$(grep -cE 'backup_if_exists "\$target"$' "$INSTALL")" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
