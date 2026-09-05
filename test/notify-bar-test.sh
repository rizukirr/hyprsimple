#!/bin/bash
# The volume and brightness notifications drew a bar that was wrong at exactly
# the two values a person is most likely to see.
#
#   filled=$((vol / 5))
#   empty=$((20 - filled))
#   bar="$(printf '█%.0s' $(seq 1 $filled))$(printf '░%.0s' $(seq 1 $empty))"
#
# printf with no arguments prints its format string once, and `seq 1 0` prints
# nothing, so each half emitted one character when it should have emitted none.
# Measured before the fix, with # and . standing in for the blocks:
#
#     0%  [#....................]  length=21  filled=1
#   100%  [####################.]  length=21  filled=20
#
# So muting showed one filled block and full volume showed an unfilled one, and
# the bar changed width at both ends.
#
# This is the trap hyprsimple-muslimtify.sh already carries a comment about and
# that committed-symlinks-test.sh works around with an explicit guard. It was
# in both notification scripts.
#
# Nothing here calls wpctl, brightnessctl or notify-send: the two functions are
# lifted out and run directly.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

for script in volume-notify.sh brightness-notify.sh; do
  sed -n '/^repeat_char() {/,/^}/p' "$BIN/$script" >"$TMP/${script%.sh}.helper"
  if [[ -s $TMP/${script%.sh}.helper ]]; then
    pass "$script defines the bar helper"
  else
    fail "$script has no repeat_char, so nothing below is testing it"
  fi
done

# Both scripts must build the bar the same way, or one of them drifts back.
check "both scripts use the helper rather than printf with seq" \
  "$(grep -lc 'repeat_char "\$filled"' "$BIN/volume-notify.sh" "$BIN/brightness-notify.sh" | wc -l | tr -d ' ')" "2"
# Comments stripped: the helper carries a comment explaining the old
# construction, and it contains the very pattern being searched for.
code_of() { sed 's/#.*//' "$1"; }
still_bad=""
for f in "$BIN/volume-notify.sh" "$BIN/brightness-notify.sh"; do
  code_of "$f" | grep -q '%.0s' && still_bad+="$(basename "$f") "
done
check "and neither still repeats with a format string" "$still_bad" ""
# Named lines rather than a count: a count is a guess, and I guessed wrong.
check "stripping comments leaves the helper definition" \
  "$(code_of "$BIN/volume-notify.sh" | grep -c '^repeat_char() {')" "1"
check "and the line that calls it" \
  "$(code_of "$BIN/volume-notify.sh" | grep -c 'bar="\$(repeat_char')" "1"

# shellcheck source=/dev/null
source "$TMP/volume-notify.helper"

bar_of() {
  local pct=$1 filled empty
  filled=$((pct / 5)); empty=$((20 - filled))
  printf '%s%s' "$(repeat_char "$filled" '#')" "$(repeat_char "$empty" '.')"
}

# --- the two ends, which is where it was wrong ------------------------------

zero=$(bar_of 0)
check "at 0 the bar is twenty characters" "${#zero}" "20"
check "and none of them is filled" "$(printf '%s' "$zero" | tr -cd '#' | wc -c | tr -d ' ')" "0"

full=$(bar_of 100)
check "at 100 the bar is twenty characters" "${#full}" "20"
check "and all of them are filled" "$(printf '%s' "$full" | tr -cd '#' | wc -c | tr -d ' ')" "20"

# --- and every step in between ----------------------------------------------

wrong_width=(); wrong_fill=()
for pct in $(seq 0 5 100); do
  b=$(bar_of "$pct")
  (( ${#b} == 20 )) || wrong_width+=("$pct:${#b}")
  f=$(printf '%s' "$b" | tr -cd '#' | wc -c | tr -d ' ')
  (( f == pct / 5 )) || wrong_fill+=("$pct:$f")
done
w=""; (( ${#wrong_width[@]} > 0 )) && w="$(printf '%s ' "${wrong_width[@]}")"
check "every step from 0 to 100 gives a twenty character bar" "$w" ""
f=""; (( ${#wrong_fill[@]} > 0 )) && f="$(printf '%s ' "${wrong_fill[@]}")"
check "and the filled count always matches the level" "$f" ""

# --- the old construction really did fail, so the checks above mean something

old_bar() {
  local pct=$1 filled empty
  filled=$((pct / 5)); empty=$((20 - filled))
  # shellcheck disable=SC2046  # the splitting is the point: this is the old code
  printf '%s%s' "$(printf '#%.0s' $(seq 1 $filled))" "$(printf '.%.0s' $(seq 1 $empty))"
}
check "the old construction gave 21 characters at 0" \
  "$(old_bar 0 | wc -c | tr -d ' ')" "21"
check "and put a filled block there" \
  "$(old_bar 0 | tr -cd '#' | wc -c | tr -d ' ')" "1"
check "and gave 21 characters at 100" "$(old_bar 100 | wc -c | tr -d ' ')" "21"

# --- the brightness copy behaves identically --------------------------------

unset -f repeat_char
# shellcheck source=/dev/null
source "$TMP/brightness-notify.helper"
b_zero=$(bar_of 0); b_full=$(bar_of 100)
check "brightness builds the same bar at 0" "$b_zero" "$zero"
check "and at 100" "$b_full" "$full"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
