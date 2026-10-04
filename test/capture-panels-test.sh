#!/bin/bash
# The screenshot menu behind Print and the recording menu behind SUPER + R are
# panels of the bar. This checks the script side of both: one keybind each, the
# script opens the right panel, a missing worker is reported, and every mode a
# panel can ask for is one the worker accepts.
#
# Nothing here opens a panel, takes a screenshot or records. qs, notify-send
# and hyprshot are stand-ins, and the PATH each run gets holds only those.
# /usr/bin is never on it: a probe that left it there once ran a real command
# on the maintainer's machine.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
BAR_QML="$REPO/default/quickshell/bar/Bar.qml"
PANEL_QML="$REPO/default/quickshell/panels/CapturePanel.qml"
SHOOTER="$BIN/screenshot.sh"
RECORDER="$BIN/screen-record.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}
for helper in pass fail check; do
  declare -F "$helper" >/dev/null || { printf 'not ok - helper %s missing\n' "$helper" >&2; exit 1; }
done

BASH_BIN="$(command -v bash)"
STUB="$TMP/bin"; mkdir -p "$STUB"
HOME_DIR="$TMP/home"; mkdir -p "$HOME_DIR/.local/bin"

cat >"$STUB/qs" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$QS_LOG"
STUBEOF
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUBEOF
cat >"$STUB/hyprshot" <<'STUBEOF'
#!/bin/bash
printf 'hyprshot %s\n' "$*" >>"$SHOT_LOG"
STUBEOF
chmod +x "$STUB"/*

check "the real qs is unreachable from the PATH the scripts get" \
  "$(PATH="$STUB" command -v qs)" "$STUB/qs"
check "and so is the real hyprshot" \
  "$(PATH="$STUB" command -v hyprshot)" "$STUB/hyprshot"

QLOG="$TMP/qs-log"; NLOG="$TMP/notifications"; LOG="$TMP/shots"
BAR_PATH="$HOME_DIR/.local/share/hyprsimple/default/quickshell"
cp "$BIN/hyprsimple-menu-exclusive.sh" "$BIN/hyprsimple-screenshot-menu.sh" "$BIN/hyprsimple-record-menu.sh" "$HOME_DIR/.local/bin/"

open_menu() {
  : >"$QLOG"; : >"$NLOG"
  QS_LOG="$QLOG" NOTIFY_LOG="$NLOG" HOME="$HOME_DIR" XDG_CONFIG_HOME="$HOME_DIR/.config" \
    HYPRSIMPLE_ROFI_PIDFILE="$TMP/no-such-pid" PATH="$STUB" \
    "$BASH_BIN" "$HOME_DIR/.local/bin/$1" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}
worker() {
  printf '#!/bin/bash\nexit 0\n' >"$HOME_DIR/.local/bin/$1"
  chmod +x "$HOME_DIR/.local/bin/$1"
}

# ---- one key each ------------------------------------------------------------
#
# There were four screenshot keybinds and six recording ones, a chord for each
# combination. Each is one key and a menu now.

binds() { sed 's/^[[:space:]]*--.*//' "$REPO/default/hypr/bindings/$1" | tr '\n' ' '; }

check "there is one screenshot keybind" "$(binds screenshot.lua | grep -o 'hl.bind(' | wc -l | tr -d ' ')" "1"
check "and it is Print" "$(binds screenshot.lua | grep -c 'hl.bind("Print"')" "1"
check "and it opens the menu rather than taking a screenshot" \
  "$(binds screenshot.lua | grep -c 'hyprsimple-screenshot-menu.sh')" "1"
check "so no bind passes a mode itself" "$(binds screenshot.lua | grep -c 'screenshot.sh ')" "0"

check "there is one recording keybind" "$(binds recording.lua | grep -o 'hl.bind(' | wc -l | tr -d ' ')" "1"
check "and it is SUPER + R" "$(binds recording.lua | grep -c 'hl.bind("SUPER + R"')" "1"
check "and it opens the menu rather than the recorder" \
  "$(binds recording.lua | grep -c 'hyprsimple-record-menu.sh')" "1"
check "so no bind passes a scope and audio mode itself" \
  "$(binds recording.lua | grep -cE 'screen-record\.sh (region|output)')" "0"

# ---- each script opens its panel ---------------------------------------------

worker screenshot.sh
open_menu hyprsimple-screenshot-menu.sh
check "the screenshot menu opens the bar's screenshot panel" \
  "$(cat "$QLOG")" "-p $BAR_PATH ipc call bar toggle screenshot"
check "and succeeds" "$(cat "$TMP/rc")" "0"

worker screen-record.sh
open_menu hyprsimple-record-menu.sh
check "the recording menu opens the bar's record panel" \
  "$(cat "$QLOG")" "-p $BAR_PATH ipc call bar toggle record"

for script in hyprsimple-screenshot-menu.sh hyprsimple-record-menu.sh; do
  check "$script goes through the helper, so an open rofi menu is closed first" \
    "$(sed 's/^[[:space:]]*#.*//' "$BIN/$script" | grep -c 'hyprsimple-menu-exclusive.sh" qs ')" "1"
done
for panel in screenshot record; do
  check "the bar has a panel named $panel" "$(grep -c "name: \"$panel\"" "$BAR_QML")" "1"
done

# ---- a missing worker is reported, not silently ignored ----------------------
#
# Said when the menu is asked for, not after a choice has been made in the
# panel, where the capture would simply not happen.

rm "$HOME_DIR/.local/bin/screenshot.sh"
open_menu hyprsimple-screenshot-menu.sh
check "with no screenshot.sh the menu says so" "$(grep -c 'screenshot.sh is missing' "$NLOG")" "1"
check "and opens nothing" "$(wc -l <"$QLOG" | tr -d ' ')" "0"
check "and fails" "$([[ $(cat "$TMP/rc") != 0 ]] && echo failed || echo succeeded)" "failed"

rm "$HOME_DIR/.local/bin/screen-record.sh"
open_menu hyprsimple-record-menu.sh
check "with no screen-record.sh the menu says so" "$(grep -c 'screen-record.sh is missing' "$NLOG")" "1"
check "and opens nothing" "$(wc -l <"$QLOG" | tr -d ' ')" "0"

# ---- what the panels ask for is what the workers accept ----------------------
#
# The panel builds a mode from two choices. The values it can choose from are
# read out of the bar here, and each resulting mode is run through the real
# worker, so a value renamed on one side and not the other is caught.

panel_block() { sed -n "/name: \"$1\"/,/^    }/p" "$BAR_QML"; }
values_of() { panel_block "$1" | grep -o 'value: "[a-z]*"' | sed 's/value: "\(.*\)"/\1/' | tr '\n' ' '; }

check "the screenshot panel offers these areas and destinations" \
  "$(values_of screenshot)" "region window monitor file clipboard "
check "the record panel offers these areas and audio sources" \
  "$(values_of record)" "region window output mic internal none "

# The rule the screenshot panel uses to name a mode, quoted from the bar. If it
# changes, the modes below have to be looked at again.
check "the screenshot panel names its modes by the rule tested here" \
  "$(panel_block screenshot | grep -c 'const mode = to === "file" ? area : area === "monitor" ? "clipboard" : area + "-clipboard"')" "1"
check "and the record panel passes its two values as they are" \
  "$(panel_block record | grep -c '"/.local/bin/screen-record.sh", ...values\]')" "1"

run_shooter() {
  : >"$LOG"; : >"$NLOG"
  SHOT_LOG="$LOG" NOTIFY_LOG="$NLOG" HOME="$HOME_DIR" PATH="$STUB" \
    "$BASH_BIN" "$SHOOTER" "$1" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

# The six modes that rule can produce, each through the real screenshot.sh
# against a stand-in hyprshot, so these are the flags it passes.
run_shooter region
check "region selects a region" "$(grep -c -- '-m region' "$LOG")" "1"
run_shooter window
check "window selects a window" "$(grep -c -- '-m window' "$LOG")" "1"
run_shooter monitor
check "monitor captures a whole screen" "$(grep -c -- '-m output' "$LOG")" "1"

run_shooter region-clipboard
check "region-clipboard selects a region" "$(grep -c -- '-m region' "$LOG")" "1"
check "and copies it without saving a file" "$(grep -c -- '--clipboard-only' "$LOG")" "1"
check "and silences hyprshot so it is announced once" "$(grep -c -- '--silent' "$LOG")" "1"
check "and announces it" "$(grep -c 'Region copied to clipboard' "$NLOG")" "1"

run_shooter window-clipboard
check "window-clipboard selects a window" "$(grep -c -- '-m window' "$LOG")" "1"
check "and copies it without saving a file" "$(grep -c -- '--clipboard-only' "$LOG")" "1"
check "and announces it" "$(grep -c 'Window copied to clipboard' "$NLOG")" "1"

run_shooter clipboard
check "clipboard copies the whole screen" "$(grep -c -- '-m output --clipboard-only' "$LOG")" "1"

run_shooter no-such-mode
check "an unknown mode captures nothing" "$(wc -c <"$LOG" | tr -d ' ')" "0"
check "and fails" "$([[ $(cat "$TMP/rc") != 0 ]] && echo failed || echo succeeded)" "failed"

# The recorder's scopes and audio modes, read out of the script. screen-record-test
# runs the recorder itself; this only checks the names agree.
recorder_code="$(sed 's/^[[:space:]]*#.*//' "$RECORDER")"
for scope in window output; do
  check "screen-record.sh knows the scope $scope" \
    "$(grep -c "\"\$SCOPE\" == \"$scope\"" <<<"$recorder_code")" "1"
done
for audio in mic internal none; do
  check "screen-record.sh knows the audio mode $audio" \
    "$(grep -cE "^[[:space:]]*$audio( \\|[^)]*)?\\)" <<<"$recorder_code")" "1"
done
check "and stop, which the record panel sends while a recording runs" \
  "$(grep -c '"$SCOPE" == "stop"' <<<"$recorder_code")" "1"
check "the record panel stops through screen-record.sh stop" \
  "$(panel_block record | grep -c '"/.local/bin/screen-record.sh", "stop"\]')" "1"

# ---- the capture waits for the panel to be gone ------------------------------
#
# The rofi menu waited for its own layer to leave before capturing, or the menu
# was in the screenshot. The panel does the same: it runs the command only once
# its window is no longer visible.
check "the panel holds the command until it has closed" \
  "$(grep -c 'onVisibleChanged: if (!visible && pending) afterClose.restart()' "$PANEL_QML")" "1"
check "and runs it from that timer and nowhere else" \
  "$(grep -c 'Quickshell.execDetached' "$PANEL_QML")" "1"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
