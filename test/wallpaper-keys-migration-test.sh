#!/bin/bash
# The wallpaper had three keys and keeps one. SUPER + ALT + W and
# SUPER + CTRL + W are bound in applications.lua, a file each user owns, so an
# update cannot take them out by replacing it. A migration removes each line
# where it is still exactly what hyprsimple shipped.
#
# This runs that migration against copies of the file in a HOME of its own, and
# checks the three things it must get right: the shipped lines go, nothing else
# in the file changes, and a line someone edited stays.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$(grep -l 'Leave the wallpaper one key' "$REPO"/migrations/*.sh | head -1)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

if [[ -z $MIGRATION ]]; then
  fail "the migration was not found, so this suite is testing nothing"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "found the migration: $(basename "$MIGRATION")"

# The file as every release before this one shipped it, kept as a fixture for
# another migration's suite. Its two lines are what installs have today.
BEFORE="$REPO/test/fixtures/presplit/bindings/applications.lua"
NEXT_KEY='"SUPER + ALT + W"'
LIVE_KEY='"SUPER + CTRL + W"'
check "the fixture still binds the next-wallpaper key" "$(grep -cF "$NEXT_KEY" "$BEFORE")" "1"
check "and the live wallpaper key" "$(grep -cF "$LIVE_KEY" "$BEFORE")" "1"

H="$TMP/home"
FILE="$H/.config/hypr/bindings/applications.lua"
fresh() {
  rm -rf "${TMP:?}/home"
  mkdir -p "$(dirname "$FILE")"
  cp "$BEFORE" "$FILE"
}
migrate() {
  HOME="$H" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

# ---- the shipped lines go, and nothing else ---------------------------------

fresh
migrate
check "the migration succeeds" "$(cat "$TMP/rc")" "0"
check "SUPER + ALT + W is gone" "$(grep -cF "$NEXT_KEY" "$FILE")" "0"
check "SUPER + CTRL + W is gone" "$(grep -cF "$LIVE_KEY" "$FILE")" "0"
check "SUPER + SHIFT + W is still bound" "$(grep -cF '"SUPER + SHIFT + W"' "$FILE")" "1"
check "the file lost those two lines and no others" \
  "$(diff <(grep -vF -e "$NEXT_KEY" -e "$LIVE_KEY" "$BEFORE") "$FILE" >/dev/null && echo same || echo differs)" "same"
check "each removal is reported" "$(grep -c '^  Removed SUPER + ' "$TMP/out")" "2"
if command -v luac >/dev/null 2>&1; then
  check "and the file still parses as lua" "$(luac -p "$FILE" 2>&1 | wc -l | tr -d ' ')" "0"
fi

# The runner writes a marker and never runs it again, but a failed update does
# run every migration from the top.
cp "$FILE" "$TMP/after-once"
migrate
check "a second run succeeds" "$(cat "$TMP/rc")" "0"
check "and changes nothing" "$(cmp -s "$TMP/after-once" "$FILE" && echo same || echo differs)" "same"

# ---- a line someone changed is theirs ---------------------------------------

fresh
sed -i 's|wallpaper-switcher.sh next"),        { description = "Next Wallpaper" }|wallpaper-switcher.sh next"), { description = "Mine" }|' "$FILE"
check "the fixture line was edited" "$(grep -c 'description = "Mine"' "$FILE")" "1"
migrate
check "an edited SUPER + ALT + W line is left alone" "$(grep -c 'description = "Mine"' "$FILE")" "1"
check "and the user is told" "$(grep -c 'Your SUPER + ALT + W line is your own' "$TMP/out")" "1"
check "while the untouched SUPER + CTRL + W line still goes" "$(grep -cF "$LIVE_KEY" "$FILE")" "0"

# ---- nothing to do is not a failure -----------------------------------------

rm -rf "${TMP:?}/home"; mkdir -p "$H"
migrate
check "with no applications.lua the migration succeeds" "$(cat "$TMP/rc")" "0"
check "and creates none" "$([[ -e $FILE ]] && echo created || echo absent)" "absent"

# ---- a new install gets the same result from the shipped file ---------------
#
# install.sh marks every migration done, so a fresh install never runs this one
# and has to start from a file without the two keys.
SHIPPED="$REPO/.config/hypr/bindings/applications.lua"
check "the shipped file does not bind SUPER + ALT + W" "$(grep -cF "$NEXT_KEY" "$SHIPPED")" "0"
check "nor SUPER + CTRL + W" "$(grep -cF "$LIVE_KEY" "$SHIPPED")" "0"
check "and still binds the picker" \
  "$(grep -c '"SUPER + SHIFT + W", hl.dsp.exec_cmd(home .. "/.local/bin/wallpaper-switcher.sh pick")' "$SHIPPED")" "1"

# What the two keys did is still reachable, from the picker.
BAR_QML="$REPO/default/quickshell/bar/Bar.qml"
check "the picker has the live wallpaper switch" \
  "$(grep -c 'switchCommand: \[Quickshell.env("HOME") + "/.local/bin/live-wallpaper-toggle.sh"\]' "$BAR_QML")" "1"
check "which reads the flag live wallpaper is recorded in" \
  "$(grep -c 'switchStateCommand: \["test", "-f", Quickshell.env("HOME") + "/.cache/live_wallpaper_enabled"\]' "$BAR_QML")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
