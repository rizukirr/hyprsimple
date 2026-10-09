#!/bin/bash
# Every panel of the bar opens through one call,
#
#   qs -p <shell> ipc call bar toggle <name>
#
# and seven of the fifteen could only be reached with the mouse: the calendar,
# the prayer times, the system panel, the microphone, the network, bluetooth
# and the notifications. Each had a button on the bar and no key.
#
# The name is a bare string on both sides, so nothing ties a key to a panel. A
# key bound to "netwrok" loads, runs, and opens nothing, with no error anywhere:
# Bar.qml's toggle() stores whatever it is given.
#
# This reads the two lists out of the code and compares them both ways. Nothing
# here runs qs or hyprctl.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAR="$REPO/default/quickshell/bar/Bar.qml"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the panels the bar has ---------------------------------------------------
#
# A panel shows up in Bar.qml as a comparison with openPanel, as the name of a
# PopupPanel, or both. Comments are stripped first, since the list of names is
# also written out in one for the reader. Lowercase only: the capitalised
# name: values in that file are labels, not panels.
#
# The two sidebars are the exception. The launcher and the notifications name
# themselves, in a string property of their own file, and Bar.qml only
# instantiates them.
panels=$({
  sed 's|^[[:space:]]*//.*||' "$BAR" |
    grep -oE 'openPanel === "[a-z]+"|name: "[a-z]+"'
  sed 's|^[[:space:]]*//.*||' "$REPO/default/quickshell/panels"/*.qml \
    "$REPO/default/quickshell/notifications"/*.qml |
    grep -oE 'property string name: "[a-z]+"'
} | sed 's/.*"\(.*\)"/\1/' | LC_ALL=C sort -u)
panel_count=$(printf '%s\n' "$panels" | grep -c .)

if (( panel_count < 10 )); then
  fail "found only $panel_count panels in Bar.qml, so this suite is not reading it"
else
  pass "read $panel_count panels out of Bar.qml"
fi

# --- the panels a key reaches -------------------------------------------------
#
# Two spellings. A bind in lua appends the name to vars.barPanel, and a helper
# script a key runs makes the call itself.
reachable=$({
  sed 's/^[[:space:]]*--.*//' "$REPO/default/hypr/vars.lua" \
    "$REPO/default/hypr/bindings"/*.lua "$REPO/.config/hypr/bindings"/*.lua |
    grep -oE 'barPanel \.\. "[a-z]+"' | sed 's/.*"\(.*\)"/\1/'
  sed 's/^[[:space:]]*#.*//' "$REPO/.local/bin"/*.sh |
    grep -oE 'ipc call bar toggle [a-z]+' | awk '{ print $NF }'
} | LC_ALL=C sort -u)

missing=$(comm -23 <(printf '%s\n' "$panels") <(printf '%s\n' "$reachable") | tr '\n' ' ')
check "every panel of the bar can be opened from the keyboard" "$missing" ""

unknown=$(comm -13 <(printf '%s\n' "$panels") <(printf '%s\n' "$reachable") | tr '\n' ' ')
check "and every name a key asks for is a panel the bar has" "$unknown" ""

check "prayer panel is supplied externally" "$(grep -cx prayer <<<"$panels")" "0"
check "external panel aliases are resolved by the registry" \
  "$(grep -c 'bar.toggle(externalPlugins.resolvePanel(panel))' "$REPO/default/quickshell/shell.qml")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
