#!/bin/bash
# The rule that hides a browser's screen-sharing bar hid ordinary windows too.
#
#   hl.window_rule({ match = { title = ".*is sharing.*" }, workspace = "special silent" })
#
# workspace is applied when a window opens, so any window whose title happened
# to contain those two words went straight to a hidden workspace and appeared
# not to open at all. Measured on a live session, with a terminal:
#
#   How Netflix is sharing your data -> ws=special:special
#
# The six titles a chromium browser gives that bar, read out of Brave's own
# locales/en-US.pak, are
#
#   $1 is sharing your screen.            $1 is sharing a window.
#   $1 is sharing your screen and audio.  $1 is sharing a window and audio.
#   $1 is sharing a Brave tab.            $1 is sharing a Brave tab and audio.
#
# so the object and the full stop are what separate the bar from prose.
#
# Nothing here opens a window. The pattern is read out of windows.lua and run
# against titles, which is the same question Hyprland asks of it.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$REPO/default/hypr/windows.lua"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the pattern, taken from the rule -----------------------------------------
#
# Read from the file rather than repeated here, so a change to the rule is
# tested rather than shadowed by a copy that still says what it used to.
pattern=$(grep -oE 'title = "[^"]*is sharing[^"]*"' "$RULES" |
  head -1 | sed 's/^title = "//; s/"$//; s/\\\\\./\\./g')

if [[ -z $pattern ]]; then
  fail "no sharing rule found in windows.lua, so this suite is reading the wrong file"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "read the pattern: $pattern"

matches() { printf '%s' "$1" | grep -qE "$pattern" && echo yes || echo no; }

# --- every title the bar can actually have ------------------------------------

for title in \
  "meet.google.com is sharing your screen." \
  "meet.google.com is sharing your screen and audio." \
  "zoom.us is sharing a window." \
  "zoom.us is sharing a window and audio." \
  "app.slack.com is sharing a Brave tab." \
  "app.slack.com is sharing a Chrome tab and audio."; do
  check "hidden: $title" "$(matches "$title")" "yes"
done

# --- and the ordinary titles that used to be caught ---------------------------

for title in \
  "How Netflix is sharing your data" \
  "Alice is sharing a document" \
  "is sharing data with partners" \
  "Who is sharing my screen? - Reddit" \
  "A guide to sharing your screen" \
  "This tab is sharing your screen"; do
  check "left alone: $title" "$(matches "$title")" "no"
done

# --- the rule is still the one Hyprland will apply ---------------------------

# Comments stripped before counting. The rule now explains itself in a comment
# that quotes all six titles, and an unanchored grep counted those explanations
# as rules: eight, against the one that exists. Anchored to the start of the
# line so a lua `--` inside a string or an arithmetic minus survives, which is
# the mistake the lua stripper in another suite made once.
code_of() { sed 's/^[[:space:]]*--.*//' "$1"; }
CODE=$(code_of "$RULES")

check "the rule still sends the bar to a silent special workspace" \
  "$(printf '%s\n' "$CODE" | grep -c 'workspace = "special silent"')" "1"
check "and there is exactly one sharing rule, not two competing ones" \
  "$(printf '%s\n' "$CODE" | grep -c 'is sharing')" "1"
check "stripping comments leaves the rules behind" \
  "$(printf '%s\n' "$CODE" | grep -c '^hl\.window_rule(')" "$(grep -c '^hl\.window_rule(' "$RULES")"

# The old pattern must not come back. Stated by name, because a widening edit
# would still pass every check above.
check "the bare two-word pattern is gone" \
  "$(printf '%s\n' "$CODE" | grep -c 'title = ".\*is sharing.\*"')" "0"

# --- windows.lua still loads --------------------------------------------------

if command -v luac >/dev/null 2>&1; then
  if luac -p "$RULES" >/dev/null 2>&1; then
    pass "windows.lua still parses as lua"
  else
    fail "windows.lua no longer parses as lua"
  fi
else
  fail "luac is not installed, so windows.lua cannot be checked"
fi

# A rule file that had been emptied would pass everything above except this.
rules=$(grep -c '^hl\.\(window\|layer\)_rule(' "$RULES")
if (( rules >= 40 )); then
  pass "windows.lua still holds $rules rules"
else
  fail "windows.lua holds only $rules rules, which is too few to be intact"
fi

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
