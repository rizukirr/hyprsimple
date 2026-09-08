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

# --- the recording indicator sits on the left and says what it is ------------
#
# It used to be a bare glyph between the battery and the clock, which reads as
# an unexplained dot. It is a labelled pill beside the prayer times now.

WBCONF="$REPO/.config/waybar/config.jsonc"
WBSTYLE="$REPO/.config/waybar/style.css"
RECSCRIPT="$BIN/waybar-screenrecording.sh"
RECMIGRATION="$REPO/migrations/1788860000.sh"

modules_line() { grep -m1 "\"$1\"" "$WBCONF"; }

check "the indicator is in modules-left" \
  "$(modules_line modules-left | grep -c 'custom/screenrecording')" "1"
check "and no longer in modules-right" \
  "$(modules_line modules-right | grep -c 'custom/screenrecording')" "0"
check "and it comes after the prayer times, not before" \
  "$(modules_line modules-left | grep -cE 'custom/muslimtify".*custom/screenrecording')" "1"

# The label, read out of the script that emits it.
check "the module says what it is rather than showing a bare glyph" \
  "$(grep -c 'recording\.\.\.' "$RECSCRIPT")" "1"
check "and still carries the active class the styling keys off" \
  "$(grep -c '"class": "active"' "$RECSCRIPT")" "1"
check "while the idle branch still emits an empty string" \
  "$(grep -c '{"text": ""}' "$RECSCRIPT")" "1"

# The background belongs to .active only. The idle module emits an empty
# string, and padding or a background on the bare id would leave an empty pill
# in the bar next to the prayer times.
active_block=$(sed -n '/^#custom-screenrecording\.active {/,/^}/p' "$WBSTYLE")
idle_block=$(sed -n '/^#custom-screenrecording {/,/^}/p' "$WBSTYLE")

check "the recording state has a background" \
  "$(printf '%s' "$active_block" | grep -c 'background-color')" "1"
check "and a border, so it reads as a pill like its neighbour" \
  "$(printf '%s' "$active_block" | grep -c '^    border:')" "1"
check "and padding to sit the text inside it" \
  "$(printf '%s' "$active_block" | grep -c '^    padding:')" "1"

check "the idle state has no background" \
  "$(printf '%s' "$idle_block" | grep -cE 'background-color|^    border: [0-9]')" "0"
check "and no padding, so nothing shows when nothing is recording" \
  "$(printf '%s' "$idle_block" | grep -c 'padding: 0')" "1"

# Anti-vacuity: both blocks were actually found. A sed range that matched
# nothing would satisfy every idle check above.
check "both style blocks were read, so those checks are not empty" \
  "$([[ -n $active_block && -n $idle_block ]] && echo both || echo missing)" "both"

# --- the migration moves it in a config that already exists ------------------
#
# waybar/config.jsonc is copied once at install and never touched again, so a
# module hyprsimple moves later does not move on an existing machine.

mig_home="$TMP/wbhome"
mkdir -p "$mig_home/.config/waybar"
cat >"$mig_home/.config/waybar/config.jsonc" <<'JSONEOF'
{
    "modules-left": ["hyprland/workspaces", "custom/muslimtify"],
    "modules-center": ["hyprland/window"],
    "modules-right": ["battery", "custom/screenrecording", "clock"],
    "custom/screenrecording": { "exec": "x" }
}
JSONEOF
before_rest=$(grep -v 'modules-left\|modules-right' "$mig_home/.config/waybar/config.jsonc")

HOME="$mig_home" bash "$RECMIGRATION" >"$TMP/wbout" 2>&1

check "the migration puts it in modules-left" \
  "$(grep -m1 'modules-left' "$mig_home/.config/waybar/config.jsonc" | grep -c 'custom/screenrecording')" "1"
check "after the prayer times" \
  "$(grep -m1 'modules-left' "$mig_home/.config/waybar/config.jsonc" | grep -cE 'custom/muslimtify".*custom/screenrecording')" "1"
check "and takes it out of modules-right" \
  "$(grep -m1 'modules-right' "$mig_home/.config/waybar/config.jsonc" | grep -c 'custom/screenrecording')" "0"
check "leaving no stray comma behind" \
  "$(grep -m1 'modules-right' "$mig_home/.config/waybar/config.jsonc" | grep -cE ',\s*,|\[\s*,|,\s*\]')" "0"
check "and changing nothing else in the file" \
  "$([[ $(grep -v 'modules-left\|modules-right' "$mig_home/.config/waybar/config.jsonc") == "$before_rest" ]] && echo same || echo changed)" "same"

# Run twice: it must not move it again or report work it did not do.
HOME="$mig_home" bash "$RECMIGRATION" >"$TMP/wbout2" 2>&1
check "running it again says it is already there" \
  "$(grep -c 'already on the left' "$TMP/wbout2")" "1"
check "and does not add a second copy" \
  "$(grep -c 'custom/screenrecording' "$mig_home/.config/waybar/config.jsonc")" "2"

# A config that has been rearranged by hand keeps its arrangement.
hand_home="$TMP/wbhand"
mkdir -p "$hand_home/.config/waybar"
cat >"$hand_home/.config/waybar/config.jsonc" <<'JSONEOF'
{
    "modules-left": ["hyprland/workspaces"],
    "modules-right": ["battery", "clock"]
}
JSONEOF
hand_before=$(cat "$hand_home/.config/waybar/config.jsonc")
HOME="$hand_home" bash "$RECMIGRATION" >"$TMP/wbout3" 2>&1
check "a config without the module in modules-right is left alone" \
  "$([[ $(cat "$hand_home/.config/waybar/config.jsonc") == "$hand_before" ]] && echo unchanged || echo edited)" "unchanged"
check "and says so" "$(grep -c 'not in modules-right' "$TMP/wbout3")" "1"

# No waybar config at all must not fail.
mkdir -p "$TMP/wbnone"
HOME="$TMP/wbnone" bash "$RECMIGRATION" >/dev/null 2>&1
check "a home with no waybar config exits 0" "$?" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
