#!/bin/bash
# SUPER + / lists the keys, and it dropped any it could not name.
#
# show-keybindings.sh parses `hyprctl binds` and ended its formatter with
#
#   if (d == "") return
#
# after a branch that only fills d for a dispatcher other than __lua. Every
# bind hyprsimple ships is __lua and every one carries a description, so that
# line never hid anything of hyprsimple's. It hid keys people add themselves:
#
#   hl.bind("SUPER + O", hl.dsp.exec_cmd("obsidian"))
#
# works, and never appeared in the one list that is supposed to say what the
# keys are, with nothing anywhere to explain the gap. Measured against a
# synthetic pair, one described and one not: only the described one was
# printed.
#
# The list itself is live, read from hyprctl on every press with no cache, so a
# binding does show up as soon as the config is reloaded. That was never the
# problem. The problem was the ones it decided not to mention.
#
# Nothing here runs hyprctl. The formatter is extracted from the script and fed
# a fixture captured from a live session, with two blocks appended that a
# working session cannot produce.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/.local/bin/show-keybindings.sh"
FIXTURE="$REPO/test/fixtures/hyprctl/binds.txt"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# gawk, not awk. The formatter uses and(), which is a gawk extension, and the
# script calls gawk by name for that reason. Asserted rather than skipped: a
# skip that fires on every CI run is a check that never runs.
if ! command -v gawk >/dev/null 2>&1; then
  fail "gawk is not installed, so the formatter cannot be checked"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "gawk is available, which the formatter needs for and()"

check "the fixture exists" "$([[ -f $FIXTURE ]] && echo yes || echo no)" "yes"

# The formatter, taken from the script so this cannot drift from it.
program=$(sed -n '/function modstr/,/END            { flush() }/p' "$SCRIPT")
if [[ $(printf '%s\n' "$program" | grep -c .) -lt 20 ]]; then
  fail "extracted only $(printf '%s\n' "$program" | grep -c .) lines of the formatter, so this is reading the wrong thing"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "extracted the formatter from the script itself"

out=$(gawk "$program" "$FIXTURE")
lines=$(printf '%s\n' "$out" | grep -c .)
if (( lines >= 5 )); then
  pass "the fixture produced $lines rows"
else
  fail "produced $lines rows, too few for the checks below to mean anything"
fi

# --- the bug -----------------------------------------------------------------

check "a lua bind with no description is listed rather than dropped" \
  "$(printf '%s\n' "$out" | grep -c '^SUPER + O ')" "1"
check "and says how to name it" \
  "$(printf '%s\n' "$out" | grep -c 'add { description = ')" "1"

# --- and everything it did right stays right ---------------------------------

check "a described bind still shows its description" \
  "$(printf '%s\n' "$out" | grep -c '^SUPER + Q  *Close Window$')" "1"
check "a non-lua bind with no description still falls back to its dispatcher" \
  "$(printf '%s\n' "$out" | grep -c '^CTRL + F1  *exec kitty$')" "1"
check "and does not get the note, having a name already" \
  "$(printf '%s\n' "$out" | grep -c '^CTRL + F1.*add { description')" "0"
check "a mouse button is named rather than left as an evdev code" \
  "$(printf '%s\n' "$out" | grep -c 'LEFT MOUSE BUTTON')" "1"
# The fixture holds six SUPER binds and one CTRL, so both branches of the
# modmask decoder are exercised rather than only the common one.
check "the SUPER modmask is decoded into a modifier name" \
  "$(printf '%s\n' "$out" | grep -c '^SUPER + ')" "6"
check "and so is a modmask that is not SUPER" \
  "$(printf '%s\n' "$out" | grep -c '^CTRL + ')" "1"

# --- nothing hyprsimple ships needs the note ---------------------------------
#
# The note is for keys someone adds. If a shipped binding ever loses its
# description this says so, rather than the note quietly becoming normal.
# `grep -o | wc -l`, not `grep -oc`. With -c, grep counts matching lines and
# ignores -o, and these files are flattened to a single line first, so both
# counts came back as 1 whatever the file held and the difference was always
# zero. The first version of this check passed against a binding stripped of
# its description, which is the one thing it exists to catch.
count_of() { sed 's/^[[:space:]]*--.*//' "$2" | tr '\n' ' ' | grep -o "$1" | wc -l; }

shipped_binds=0
shipped_descs=0
for f in "$REPO/default/hypr/bindings"/*.lua "$REPO/default/hypr/bindings.lua" \
  "$REPO/.config/hypr/bindings"/*.lua; do
  [[ -f $f ]] || continue
  shipped_binds=$((shipped_binds + $(count_of 'hl\.bind(' "$f")))
  shipped_descs=$((shipped_descs + $(count_of 'description = ' "$f")))
done
if (( shipped_binds < 40 )); then
  fail "counted only $shipped_binds shipped bindings, so this is not reading them"
else
  pass "counted $shipped_binds shipped bindings"
fi
check "and every one of them carries a description" "$shipped_descs" "$shipped_binds"

# --- and the file people write binds in says so ------------------------------
#
# applications.lua showed { description = ... } in both of its examples and
# never said what it is for. The key works without one, so it is the easy part
# to drop, and the consequence is invisible: the bind simply is not in the
# list.

APPS="$REPO/.config/hypr/bindings/applications.lua"
check "the user's keybind file says a bind wants a description" \
  "$(grep -c 'Give every bind a description' "$APPS")" "1"
check "and says where the missing one would have shown up" \
  "$(grep -c 'SUPER + /' "$APPS")" "1"
check "while both worked examples still carry one" \
  "$(grep -c '^--   hl.bind(.*description = ' "$APPS")" "2"

# --- delivered to installs that already exist --------------------------------
#
# .config is copied once and never overwritten, so a comment added here reaches
# new installs only. #91 shipped a theme fix that way and it never arrived.

MIGRATION="$REPO/migrations/1788699662.sh"
check "a migration carries it" "$([[ -f $MIGRATION ]] && echo yes || echo no)" "yes"
# Not "and it is the newest migration". #95's suite asserted that about its
# own, which was true that day and false as soon as this one was added.
# Ordering across all migrations belongs in migration-naming-test.sh, and does
# not want repeating per migration.
check "with a ten digit name, so it globs in order" \
  "$(basename "$MIGRATION" .sh | grep -cE '^[0-9]{10}$')" "1"

MTMP="$(mktemp -d)"
# A trap rather than a delete at the end. Several checks above can exit early,
# and suite-hygiene-test.sh fails any suite that makes a temp directory without
# one, which is how the first version of this was caught.
trap 'rm -rf "${MTMP:?}"' EXIT
MHOME="$MTMP/fakehome"
setup_home() { rm -rf "${MTMP:?}/fakehome"; mkdir -p "$MHOME/.config/hypr/bindings"; }
run_migration() {
  HOME="$MHOME" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$MTMP/out" 2>&1
}
has_note() { grep -c 'Give every bind a description' "$MHOME/.config/hypr/bindings/applications.lua" 2>/dev/null; }

# The file as it stood before this change, kept as a fixture rather than read
# out of git. CI checks out shallow, so a suite asking git for an old version
# is handed the current one, and suite-hygiene-test.sh fails any suite that
# tries. The first version of this did exactly that, and the check flipped from
# passing to failing the moment the change was committed, because HEAD then
# held the new file.
#
# Copied with cp, not written from a command substitution: `$(...)` drops the
# trailing newline, which changes the checksum, and an unedited copy then reads
# as edited.
PRE="$REPO/test/fixtures/pre-description-note/applications.lua"
recorded=$(grep -oE '^SHIPPED_SUM="[a-f0-9]+"' "$MIGRATION" | cut -d'"' -f2)
check "the fixture is the version the migration records" \
  "$(md5sum "$PRE" | cut -d' ' -f1)" "$recorded"
check "and it is not already carrying the note, or this proves nothing" \
  "$(grep -c 'Give every bind a description' "$PRE")" "0"

setup_home
cp "$PRE" "$MHOME/.config/hypr/bindings/applications.lua"
run_migration
check "an unedited copy gains the note" "$(has_note)" "1"
check "and says so" "$(grep -c 'Added the note' "$MTMP/out")" "1"

setup_home
printf -- '-- my own file\nhl.bind("SUPER + Z", hl.dsp.exec_cmd("zed"))\n' \
  >"$MHOME/.config/hypr/bindings/applications.lua"
run_migration
check "an edited copy is left alone" "$(has_note)" "0"
check "with its own first line intact" \
  "$(head -1 "$MHOME/.config/hypr/bindings/applications.lua")" "-- my own file"
check "and the note is printed instead, so it is not simply lost" \
  "$(grep -c 'The note it would have added' "$MTMP/out")" "1"

setup_home
cp "$APPS" "$MHOME/.config/hypr/bindings/applications.lua"
run_migration
check "a copy already carrying it says nothing beyond its title" \
  "$(grep -vc 'Say in your keybind file' "$MTMP/out")" "0"

setup_home
run_migration
check "and a home without the file is not given one" \
  "$([[ -f $MHOME/.config/hypr/bindings/applications.lua ]] && echo created || echo absent)" "absent"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
