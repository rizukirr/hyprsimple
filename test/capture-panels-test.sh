#!/bin/bash
# Print takes a screenshot straight away, by picking an area on a frozen
# screen. SUPER + R opens the recording menu, which is a panel of the bar. This
# checks the script side of both: one keybind each, the picker, the modes
# screenshot.sh has, and that what the record panel asks for is what the
# recorder accepts.
#
# Nothing here opens a panel, takes a screenshot or records. qs, notify-send,
# hyprshot, hyprctl, slurp, grim, hyprpicker and wl-copy are stand-ins, and the
# PATH each run gets holds only those and a few real tools linked in by name.
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
cp "$BIN/hyprsimple-menu-exclusive.sh" "$BIN/hyprsimple-record-menu.sh" "$HOME_DIR/.local/bin/"

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
# combination. Each is one key now. Print picks on screen, SUPER + R opens a menu.

binds() { sed 's/^[[:space:]]*--.*//' "$REPO/default/hypr/bindings/$1" | tr '\n' ' '; }

check "there is one screenshot keybind" "$(binds screenshot.lua | grep -o 'hl.bind(' | wc -l | tr -d ' ')" "1"
check "and it is Print" "$(binds screenshot.lua | grep -c 'hl.bind("Print"')" "1"
check "and it goes straight to the picker" \
  "$(binds screenshot.lua | grep -c 'screenshot.sh smart"')" "1"
check "with no menu in between" "$(binds screenshot.lua | grep -c 'screenshot-menu')" "0"
check "and the menu script is gone" \
  "$([[ -e $BIN/hyprsimple-screenshot-menu.sh ]] && echo present || echo gone)" "gone"
check "and so is the bar's screenshot panel" "$(grep -c 'name: "screenshot"' "$BAR_QML")" "0"

check "there is one recording keybind" "$(binds recording.lua | grep -o 'hl.bind(' | wc -l | tr -d ' ')" "1"
check "and it is SUPER + R" "$(binds recording.lua | grep -c 'hl.bind("SUPER + R"')" "1"
check "and it opens the menu rather than the recorder" \
  "$(binds recording.lua | grep -c 'hyprsimple-record-menu.sh')" "1"
check "so no bind passes a scope and audio mode itself" \
  "$(binds recording.lua | grep -cE 'screen-record\.sh (region|output)')" "0"

# ---- the recording menu opens its panel --------------------------------------

worker screen-record.sh
open_menu hyprsimple-record-menu.sh
check "the recording menu opens the bar's record panel" \
  "$(cat "$QLOG")" "-p $BAR_PATH ipc call bar toggle record"

check "and succeeds" "$(cat "$TMP/rc")" "0"
check "it goes through the helper, so an open rofi menu is closed first" \
  "$(sed 's/^[[:space:]]*#.*//' "$BIN/hyprsimple-record-menu.sh" | grep -c 'hyprsimple-menu-exclusive.sh" qs ')" "1"
check "the bar has a panel named record" "$(grep -c 'name: "record"' "$BAR_QML")" "1"

# ---- a missing worker is reported, not silently ignored ----------------------
#
# Said when the menu is asked for, not after a choice has been made in the
# panel, where the capture would simply not happen.

rm "$HOME_DIR/.local/bin/screen-record.sh"
open_menu hyprsimple-record-menu.sh
check "with no screen-record.sh the menu says so" "$(grep -c 'screen-record.sh is missing' "$NLOG")" "1"
check "and opens nothing" "$(wc -l <"$QLOG" | tr -d ' ')" "0"
check "and fails" "$([[ $(cat "$TMP/rc") != 0 ]] && echo failed || echo succeeded)" "failed"

# ---- what the record panel asks for is what the recorder accepts -------------
#
# The values the panel can choose from are read out of the bar here, so a value
# renamed on one side and not the other is caught.

panel_block() { sed -n "/name: \"$1\"/,/^    }/p" "$BAR_QML"; }
values_of() { panel_block "$1" | grep -o 'value: "[a-z]*"' | sed 's/value: "\(.*\)"/\1/' | tr '\n' ' '; }

check "the record panel offers these areas and audio sources" \
  "$(values_of record)" "region window output mic internal none "

check "and passes its two values as they are" \
  "$(panel_block record | grep -c '"/.local/bin/screen-record.sh", ...values\]')" "1"

run_shooter() {
  : >"$LOG"; : >"$NLOG"
  SHOT_LOG="$LOG" NOTIFY_LOG="$NLOG" HOME="$HOME_DIR" PATH="$STUB" \
    "$BASH_BIN" "$SHOOTER" "$1" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

# ---- the modes screenshot.sh has besides the picker ---------------------------
#
# Each through the real screenshot.sh against a stand-in hyprshot, so these are
# the flags it passes. Nothing binds them now, and they stay for scripts and
# for a binding of the user's own.
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

# ---- the picker behind Print --------------------------------------------------
#
# screenshot.sh smart, run for real against stand-ins. hyprctl answers with two
# monitors and five windows, slurp answers with whatever the case chose, grim
# writes a file, and hyprpicker, which freezes the screen, records its pid so
# the checks can see whether it was left running.

PICK="$TMP/pick"; mkdir -p "$PICK"
PBIN="$PICK/bin"; mkdir -p "$PBIN"
for tool in jq date mkdir sleep cat; do ln -s "$(command -v "$tool")" "$PBIN/$tool"; done
cp "$STUB/notify-send" "$PBIN/"

# The second monitor is rotated and scaled: 2160x3840 at scale 2 turned on its
# side is 1920x1080 in the layout. Workspace 1 is on the focused monitor.
cat >"$PBIN/hyprctl" <<'STUBEOF'
#!/bin/bash
case "$1" in
monitors)
  cat <<'JSON'
[{"name":"A","x":0,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"focused":true,"activeWorkspace":{"id":1}},
 {"name":"B","x":1920,"y":0,"width":2160,"height":3840,"scale":2,"transform":1,"focused":false,"activeWorkspace":{"id":2}}]
JSON
  ;;
clients)
  cat <<'JSON'
[{"workspace":{"id":1},"at":[10,50],"size":[900,1000],"hidden":false},
 {"workspace":{"id":1},"at":[920,50],"size":[990,1000],"hidden":false},
 {"workspace":{"id":1},"at":[920,50],"size":[990,1000],"hidden":false},
 {"workspace":{"id":1},"at":[300,300],"size":[200,100],"hidden":true},
 {"workspace":{"id":2},"at":[1930,50],"size":[500,500],"hidden":false}]
JSON
  ;;
esac
STUBEOF
cat >"$PBIN/slurp" <<'STUBEOF'
#!/bin/bash
cat >"$SLURP_INPUT"
[[ -n ${SLURP_PICK:-} ]] || exit 1
printf '%s\n' "$SLURP_PICK"
STUBEOF
cat >"$PBIN/grim" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$GRIM_LOG"
[[ -e $GRIM_FAILS ]] && exit 1
printf 'picture of %s\n' "$2" >"${*: -1}"
STUBEOF
cat >"$PBIN/wl-copy" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >"$COPY_ARGS"
cat >"$COPIED"
STUBEOF
cat >"$PBIN/hyprpicker" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$$" >"$FREEZE_PID"
printf '%s\n' "$*" >"$FREEZE_ARGS"
while :; do sleep 0.05; done
STUBEOF
chmod +x "$PBIN"/*

check "the real grim is unreachable from the picker's PATH" "$(PATH="$PBIN" command -v grim)" "$PBIN/grim"
check "and so is the real wl-copy" "$(PATH="$PBIN" command -v wl-copy)" "$PBIN/wl-copy"

PHOME="$PICK/home"
pick() {
  rm -rf "$PHOME"; mkdir -p "$PHOME"
  : >"$PICK/grim-log"; : >"$NLOG"; rm -f "$PICK/copied" "$PICK/copy-args" "$PICK/freeze-pid" "$PICK/slurp-input"
  SLURP_PICK="${1-}" SLURP_INPUT="$PICK/slurp-input" GRIM_LOG="$PICK/grim-log" GRIM_FAILS="$PICK/grim-fails" \
    COPIED="$PICK/copied" COPY_ARGS="$PICK/copy-args" FREEZE_PID="$PICK/freeze-pid" FREEZE_ARGS="$PICK/freeze-args" \
    NOTIFY_LOG="$NLOG" HOME="$PHOME" HYPRSIMPLE_SCREENSHOT_FREEZE_WAIT=0.05 PATH="$PBIN" \
    "$BASH_BIN" "$SHOOTER" smart >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}
shots() { find "$PHOME/Pictures/Screenshots" -type f 2>/dev/null; }
freeze_left_running() {
  local pid; pid=$(cat "$PICK/freeze-pid" 2>/dev/null)
  [[ -n $pid && -e /proc/$pid ]] && echo running || echo gone
}

# Dragging a region.
pick "100,100 400x300"
check "a dragged region is captured as dragged" "$(cat "$PICK/grim-log")" "-g 100,100 400x300 $(shots)"
check "into one file under Pictures/Screenshots" "$(shots | wc -l | tr -d ' ')" "1"
check "which is a png named for when it was taken" \
  "$(shots | grep -cE '/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}_screenshot\.png$')" "1"
check "and it is copied to the clipboard as well, the same bytes" \
  "$(cmp -s "$(shots)" "$PICK/copied" && echo same || echo differs)" "same"
check "as an image" "$(cat "$PICK/copy-args")" "--type image/png"
check "and announced once" "$(grep -c 'Saved to ~/Pictures/Screenshots/.* and copied to the clipboard' "$NLOG")" "1"
check "and succeeds" "$(cat "$TMP/rc")" "0"
check "the screen was frozen while picking" "$(cat "$PICK/freeze-args")" "-r -z"
check "and is not left frozen" "$(freeze_left_running)" "gone"

# The boxes slurp can snap to.
check "slurp is offered both monitors, the rotated and scaled one in layout size" \
  "$(sed -n 1,2p "$PICK/slurp-input" | tr '\n' ';')" "0,0 1920x1080;1920,0 1920x1080;"
check "and the windows on the active workspace, each place once, hidden ones left out" \
  "$(sed -n '3,$p' "$PICK/slurp-input" | tr '\n' ';')" "10,50 900x1000;920,50 990x1000;"

# A click. slurp answers with the box it snapped to, which is passed on as it is.
pick "920,50 990x1000"
check "a click on a window captures that window" "$(cut -d' ' -f1-3 "$PICK/grim-log")" "-g 920,50 990x1000"

# A click slurp reports as a tiny area of its own is snapped here.
pick "1000,500 1x1"
check "a bare click inside a window snaps to it, not to the monitor behind" \
  "$(cut -d' ' -f1-3 "$PICK/grim-log")" "-g 920,50 990x1000"
pick "5,5 2x2"
check "a bare click outside every window snaps to its monitor" \
  "$(cut -d' ' -f1-3 "$PICK/grim-log")" "-g 0,0 1920x1080"
pick "2000,500 1x1"
check "a bare click on the other monitor snaps to that one" \
  "$(cut -d' ' -f1-3 "$PICK/grim-log")" "-g 1920,0 1920x1080"

# Escape.
pick ""
check "a cancelled pick captures nothing" "$(wc -c <"$PICK/grim-log" | tr -d ' ')" "0"
check "and copies nothing, so the clipboard is left as it was" \
  "$([[ -e $PICK/copied ]] && echo copied || echo untouched)" "untouched"
check "and says nothing" "$(wc -c <"$NLOG" | tr -d ' ')" "0"
check "and is not an error" "$(cat "$TMP/rc")" "0"
check "and the screen is not left frozen" "$(freeze_left_running)" "gone"

# A capture that fails.
: >"$PICK/grim-fails"
pick "100,100 400x300"
rm "$PICK/grim-fails"
check "a capture that fails is reported" "$(grep -c 'Could not capture the screen' "$NLOG")" "1"
check "and copies nothing" "$([[ -e $PICK/copied ]] && echo copied || echo untouched)" "untouched"
check "and fails" "$([[ $(cat "$TMP/rc") != 0 ]] && echo failed || echo succeeded)" "failed"
check "and the screen is not left frozen" "$(freeze_left_running)" "gone"

# A missing tool is named, before the screen is frozen.
mv "$PBIN/grim" "$PBIN/grim.away"
pick "100,100 400x300"
mv "$PBIN/grim.away" "$PBIN/grim"
check "a missing tool is named" "$(grep -c 'grim is not installed' "$NLOG")" "1"
check "before the screen is frozen" "$([[ -e $PICK/freeze-pid ]] && echo frozen || echo not)" "not"

# slurp's own layer must be gone when the picture is taken. Hyprland would fade
# it out, and the fade would be in the picture.
check "Hyprland does not animate slurp's layer" \
  "$(sed 's/^[[:space:]]*--.*//' "$REPO/default/hypr/windows.lua" | grep -c 'namespace = "selection" }, no_anim = true')" "1"

# ---- the capture waits for the panel to be gone ------------------------------
#
# A recording must not start with the record panel still on screen, or the
# panel is in the first frames. The panel runs its command only once its window
# is no longer visible.
check "the panel holds the command until it has closed" \
  "$(grep -c 'onVisibleChanged: if (!visible && pending) afterClose.restart()' "$PANEL_QML")" "1"
check "and runs it from that timer and nowhere else" \
  "$(grep -c 'Quickshell.execDetached' "$PANEL_QML")" "1"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
