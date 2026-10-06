#!/bin/bash
# The bar is a Quickshell config shipped in default/quickshell. This checks the
# script that starts, restarts and toggles it, and the migration that moves an
# existing install from waybar to it. Everything that would touch the machine
# is stubbed: pgrep, pkill, uwsm, qs, pacman and sudo.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
RESTART="$BIN/hyprsimple-restart-bar.sh"
MIGRATION="$(grep -l 'Replace waybar with the Quickshell bar' "$REPO"/migrations/*.sh | head -1)"
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

# ---- what ships -------------------------------------------------------------

BAR_DIR="$REPO/default/quickshell"
check "the bar's entry point ships" \
  "$([[ -f $BAR_DIR/shell.qml ]] && echo present || echo missing)" "present"
check "and its colours come from the file the theme delivery writes" \
  "$(grep -c '/.config/quickshell/theme-active.json' "$BAR_DIR/theme/Theme.qml")" "1"
check "and the delivery really writes that file" \
  "$(grep -c '\.config/quickshell/theme-active.json' "$BIN/hyprsimple-theme-deliver.sh")" "1"
check "the migration was found" "$([[ -n $MIGRATION ]] && echo found || echo missing)" "found"

# The app launcher is a panel of the bar. Its search is plain JavaScript in its
# own file, and it starts apps through uwsm so they run in the session's scope
# like an app started from a keybinding.
LAUNCHER="$BAR_DIR/panels/LauncherPanel.qml"
check "the launcher ships" "$([[ -f $LAUNCHER ]] && echo present || echo missing)" "present"
check "with its search" "$([[ -f $BAR_DIR/launcher/search.js ]] && echo present || echo missing)" "present"
check "and the bar creates it" "$(grep -c 'LauncherPanel {' "$BAR_DIR/bar/Bar.qml")" "1"
check "it starts apps through uwsm, by desktop id" \
  "$(grep -c 'execDetached(\["uwsm", "app", "--", app.id + ".desktop"\])' "$LAUNCHER")" "1"
check "and the name the keybinding opens is the one the panel answers to" \
  "$(grep -c 'readonly property string name: "launcher"' "$LAUNCHER")" "1"

# The panels and the launcher animate themselves. Hyprland's own layer
# animation on top of that played a second fade on open and close.
PANEL_NAMESPACE="$(grep -ho 'WlrLayershell.namespace: "[^"]*"' "$BAR_DIR/panels/PopupPanel.qml" "$LAUNCHER" | sort -u | sed 's/.*"\(.*\)"/\1/')"
check "the panels and the launcher share one layer namespace" "$PANEL_NAMESPACE" "quickshell-panel"
check "and Hyprland is told not to animate it" \
  "$(sed 's/^[[:space:]]*--.*//' "$REPO/default/hypr/windows.lua" | grep -c "namespace = \"$PANEL_NAMESPACE\" }, no_anim = true")" "1"

# The theme and wallpaper pickers build their rows when the bar starts, so a
# picker opens already on the choice in use. Each row decoded its picture then
# as well, and held it for a panel that was closed. Measured with the bar
# hidden, on one monitor, as private memory eight seconds after start:
#
#   pictures loaded at start         84, 88, 88 MB
#   pictures loaded while on screen  76, 79, 72 MB
#
# The saving lasts until a picker is first opened. After one open and close the
# two measure the same, 92 MB against 93.
PICKER_PANEL="$BAR_DIR/panels/ImagePickerPanel.qml"
picker_code="$(sed 's|^[[:space:]]*//.*||' "$PICKER_PANEL")"
check "a picker row has one picture" "$(grep -c '^[[:space:]]*source: ' <<<"$picker_code")" "1"
check "and loads it only while the panel is on screen" \
  "$(grep -c '^[[:space:]]*source: root\.visible && ' <<<"$picker_code")" "1"

# An untouched bar drew about eleven frames a second.
#
# The system panel's meters animate to each new value, and they get one every
# two seconds whether the panel is open or not. A running animation makes every
# visible window draw, so the closed panel kept the bar drawing. Counted from
# Qt's render loop log on a copy of the bar nobody touched, over twenty seconds:
#
#   as shipped                           222 frames, 2.1% of a core
#   stats read every ten minutes           0 frames
#   meter animated only while on screen    0 frames, 0.1% of a core
#
# With the panel open the meters still animate: 67 frames in six seconds.
METER="$BAR_DIR/components/Meter.qml"
meter_code="$(sed 's|^[[:space:]]*//.*||' "$METER")"
check "a meter animates its width" "$(grep -c 'Behavior on width' <<<"$meter_code")" "1"
check "and only in a window that is on screen" \
  "$(grep -c 'Behavior on width { enabled: root.Window.window?.visible ?? false; Anim {} }' <<<"$meter_code")" "1"

# ---- stubs ------------------------------------------------------------------
#
# Every stub appends what it was called with to one log, in order. Which
# programs count as running is read from files in $STATE, so a case sets up the
# machine by touching them.

STUB="$TMP/bin"; STATE="$TMP/state"; LOG="$TMP/log"
mkdir -p "$STUB" "$STATE"

cat >"$STUB/pgrep" <<'STUBEOF'
#!/bin/bash
# -x waybar asks about waybar, -f asks about the bar by its command line.
if [[ $* == *waybar* ]]; then [[ -e $STATE/waybar ]]; exit; fi
[[ -e $STATE/bar ]]
STUBEOF
cat >"$STUB/pkill" <<'STUBEOF'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$LOG"
if [[ $* == *waybar* ]]; then rm -f "$STATE/waybar"; else rm -f "$STATE/bar"; fi
exit 0
STUBEOF
cat >"$STUB/uwsm" <<'STUBEOF'
#!/bin/bash
printf 'uwsm %s\n' "$*" >>"$LOG"
STUBEOF
cat >"$STUB/setsid" <<'STUBEOF'
#!/bin/bash
"$@"
STUBEOF
cat >"$STUB/qs" <<'STUBEOF'
#!/bin/bash
printf 'qs %s\n' "$*" >>"$LOG"
# kill asks the bar to quit. It does, unless the case says this one is stuck.
if [[ $1 == kill && ! -e $STATE/quit-ignored ]]; then rm -f "$STATE/bar"; fi
exit 0
STUBEOF
cat >"$STUB/pacman" <<'STUBEOF'
#!/bin/bash
[[ $1 == -Qi ]] && { [[ -e $STATE/waybar-package ]]; exit; }
printf 'pacman %s\n' "$*" >>"$LOG"
[[ -e $STATE/removal-fails ]] && exit 1
rm -f "$STATE/waybar-package"
STUBEOF
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
printf 'sudo\n' >>"$LOG"
"$@"
STUBEOF
chmod +x "$STUB"/*

reset() { rm -f "$STATE"/*; : >"$LOG"; }
started() { grep -c '^uwsm app -- qs -p ' "$LOG"; }
run_restart() {
  STATE="$STATE" LOG="$LOG" HYPRSIMPLE_PATH="$TMP/install" HOME="$TMP/home" \
    PATH="$STUB:/usr/bin:/bin" bash "$RESTART" "$@" >/dev/null 2>&1
  # The script backgrounds the launch. The stubs return at once, so a short
  # wait is enough for the line to land in the log.
  sleep 0.2
}

# ---- the restart script -----------------------------------------------------

reset
run_restart
check "with no argument the bar is started even when none was running" "$(started)" "1"
check "from the config the install ships" \
  "$(grep -c "^uwsm app -- qs -p $TMP/install/default/quickshell$" "$LOG")" "1"

reset
run_restart --if-running
check "--if-running does nothing when no bar is up" "$(started)" "0"

reset; : >"$STATE/bar"
run_restart --if-running
check "--if-running restarts a bar that is up" "$(started)" "1"

# The old bar is asked to quit, not signalled.
#
# Quickshell does not take its child processes down when a signal ends it, and
# the bar has one that never exits by itself: the dbus-monitor that watches
# hypridle. Every restart left one behind, owned by systemd, until logout.
# Measured on Quickshell 0.3.1 with a config whose only child is a sleep:
#
#   SIGTERM, what pkill sends   the shell exits, the sleep survives
#   SIGHUP                      the shell exits, the sleep survives
#   qs kill -p <config>         the shell exits, the sleep is gone
check "after asking the old one to quit" \
  "$(grep -c "^qs kill -p $TMP/install/default/quickshell$" "$LOG")" "1"
check "and without signalling a bar that did quit" "$(grep -c '^pkill ' "$LOG")" "0"
quit_line=$(grep -n '^qs kill ' "$LOG" | head -1 | cut -d: -f1)
start_line=$(grep -n '^uwsm app -- qs -p ' "$LOG" | head -1 | cut -d: -f1)
check "and the new bar starts after the old one was told to go" \
  "$(( ${quit_line:-0} > 0 && ${start_line:-0} > ${quit_line:-0} ))" "1"

# A bar that does not answer still has to go, or two of them run at once.
reset; : >"$STATE/bar"; : >"$STATE/quit-ignored"
run_restart --if-running
check "a bar that ignores the request is signalled" "$(grep -c '^pkill -f ' "$LOG")" "1"
check "only after it was asked" \
  "$(( $(grep -n '^pkill ' "$LOG" | head -1 | cut -d: -f1) > $(grep -n '^qs kill ' "$LOG" | head -1 | cut -d: -f1) ))" "1"
check "and the new bar is still started" "$(started)" "1"

reset
run_restart
check "with no bar running nothing is asked to quit" "$(grep -c '^qs kill ' "$LOG")" "0"

reset; : >"$STATE/bar"
run_restart --toggle
# Hidden, not stopped. The bar also shows the notifications, and a stopped one
# would drop them without a word.
check "--toggle asks a running bar to hide or show itself" \
  "$(grep -c "^qs -p $TMP/install/default/quickshell ipc call bar toggleVisible$" "$LOG")" "1"
check "without stopping it" "$(grep -c '^pkill ' "$LOG")" "0"
check "and does not start another" "$(started)" "0"

reset
run_restart --toggle
check "--toggle starts a stopped bar" "$(started)" "1"

# The bar is matched by its config path. Killing by the process name would
# take down any other Quickshell config the user runs.
check "the bar is never killed by process name" \
  "$(sed 's/#.*//' "$RESTART" | grep -cE 'pkill +(-x +)?qs( |$)|killall')" "0"

# ---- the update restarts a bar whose files it changed -----------------------
#
# Quickshell reloads a running config as its files change, and a pull changes
# them one at a time. A reload partway through read a file that used a type
# whose own file had not arrived yet, failed, and was never retried. Checked in
# the code here. The behaviour was confirmed by running the real update against
# a throwaway install, which this suite does not rebuild.
UPDATER="$BIN/hyprsimple-update.sh"
updater_code="$(sed 's/^[[:space:]]*#.*//' "$UPDATER")"
check "the update restarts the bar when it is running" \
  "$(grep -c 'hyprsimple-restart-bar.sh" --if-running' <<<"$updater_code")" "1"
check "only when the pull touched the bar" \
  "$(grep -c 'diff --name-only "\$PREV_COMMIT" HEAD -- default/quickshell' <<<"$updater_code")" "1"
restart_line=$(grep -n 'hyprsimple-restart-bar.sh" --if-running' "$UPDATER" | cut -d: -f1)
migrate_line=$(grep -n 'hyprsimple-migrate.sh"$' "$UPDATER" | cut -d: -f1)
check "and after the migrations, so a bar a migration started is not restarted twice in a row for nothing" \
  "$(( restart_line > migrate_line ))" "1"

# ---- the migration ----------------------------------------------------------

run_migration() {
  mkdir -p "$TMP/home/.local/bin"
  cp "$RESTART" "$TMP/home/.local/bin/"
  STATE="$STATE" LOG="$LOG" HYPRSIMPLE_PATH="$TMP/install" HOME="$TMP/home" \
    PATH="${MIGRATION_PATH:-$STUB:/usr/bin:/bin}" "$@" "$BASH" "$MIGRATION" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
  sleep 0.2
}

reset; : >"$STATE/waybar"; : >"$STATE/waybar-package"
run_migration env HYPRLAND_INSTANCE_SIGNATURE=test
check "in a session, the migration stops waybar" "$(grep -c '^pkill -x waybar$' "$LOG")" "1"
check "and starts the bar" "$(started)" "1"
check "and removes the waybar package" "$(grep -c '^pacman -Rns --noconfirm waybar$' "$LOG")" "1"
check "and succeeds" "$(cat "$TMP/rc")" "0"

reset
run_migration env HYPRLAND_INSTANCE_SIGNATURE=test
check "with no waybar installed it never reaches sudo" "$(grep -c '^sudo$' "$LOG")" "0"
check "and still starts the bar" "$(started)" "1"

reset; : >"$STATE/waybar-package"
run_migration env -u HYPRLAND_INSTANCE_SIGNATURE
check "outside a session it starts nothing" "$(started)" "0"
check "and says the bar starts at the next login" "$(grep -c 'next login' "$TMP/out")" "1"

reset; : >"$STATE/waybar-package"; : >"$STATE/removal-fails"
run_migration env HYPRLAND_INSTANCE_SIGNATURE=test
check "a package removal that fails does not fail the update" "$(cat "$TMP/rc")" "0"
check "and says how to remove it by hand" "$(grep -c 'sudo pacman -Rns waybar' "$TMP/out")" "1"

# The update carries on when a package fails to install, so quickshell can be
# missing when the migration runs. Autostart already launches it instead of
# waybar, so stopping waybar as well would leave no bar at all.
#
# The system directories are left off PATH for this run, because a machine with
# quickshell installed has a real qs there. Only the stubs, minus qs, and the
# few tools the migration needs are reachable.
NOQS="$TMP/no-qs"; mkdir -p "$NOQS"
for tool in "$STUB"/*; do
  [[ $(basename "$tool") == qs ]] || ln -s "$tool" "$NOQS/"
done
for tool in rm env; do
  ln -s "$(command -v "$tool")" "$NOQS/"
done
reset; : >"$STATE/waybar"; : >"$STATE/waybar-package"
MIGRATION_PATH="$NOQS" run_migration "$(command -v env)" HYPRLAND_INSTANCE_SIGNATURE=test
check "without quickshell the migration fails, so it runs again next time" "$(cat "$TMP/rc")" "1"
check "and leaves waybar running" "$([[ -e $STATE/waybar ]] && echo running || echo stopped)" "running"
check "and installed" "$([[ -e $STATE/waybar-package ]] && echo installed || echo removed)" "installed"
check "and says how to install quickshell" "$(grep -c 'sudo pacman -S quickshell' "$TMP/out")" "1"

# The update copies scripts into ~/.local/bin and never removes one.
STALE=(hyprsimple-refresh-waybar.sh waybar-muslimtify.sh waybar-screenrecording.sh
  hyprsimple-audio-menu.sh)
reset
mkdir -p "$TMP/home/.local/bin"
for stale in "${STALE[@]}" hyprsimple-restart-waybar.sh volume-notify.sh; do
  : >"$TMP/home/.local/bin/$stale"
done
run_migration env HYPRLAND_INSTANCE_SIGNATURE=test
left=0
for stale in "${STALE[@]}"; do
  [[ -e $TMP/home/.local/bin/$stale ]] && left=$((left + 1))
done
check "the scripts that existed for waybar and the rofi sound menu are removed" "$left" "0"
check "and a script that still ships is left alone" \
  "$([[ -e $TMP/home/.local/bin/volume-notify.sh ]] && echo kept || echo removed)" "kept"
# The update that runs this migration is the old one, and it calls this script
# after the migrations. Removing it made that run end with an error.
check "and so is the waybar restart script, which the running update still calls" \
  "$([[ -e $TMP/home/.local/bin/hyprsimple-restart-waybar.sh ]] && echo kept || echo removed)" "kept"
# Every name the migration removes must really be gone from the repository, or
# the next update would copy it back and the one after would not remove it.
still_shipped=0
for stale in "${STALE[@]}"; do
  [[ -e $BIN/$stale ]] && still_shipped=$((still_shipped + 1))
done
check "and none of the removed ones still ships" "$still_shipped" "0"

# ---- prayer times -----------------------------------------------------------
#
# The times change at midnight and when the config does. A bar that ran
# muslimtify on a timer spawned it thousands of times a day for nothing, and
# once per monitor, so the timer that is left may only run after a failed read
# and the service is made once for every bar.

SERVICE="$BAR_DIR/muslimtify/services/Muslimtify.qml"
check "the only timer that reads prayer times again runs after a failed read" \
  "$(grep -B4 'onTriggered: root.refresh()' "$SERVICE" | grep -c 'running: .*root.todayFailed')" "1"
check "and nothing else reads them on a timer" \
  "$(grep -c 'onTriggered: root.refresh()' "$SERVICE")" "1"
check "the prayer service is made once, in the shell" \
  "$(grep -c '^ *Muslimtify {' "$BAR_DIR/shell.qml")" "1"
check "and not once per bar" \
  "$(grep -c '^ *Muslimtify {' "$BAR_DIR/bar/Bar.qml")" "0"

# The same went for the keep-awake button, which ran pgrep every 5 seconds on
# every monitor, and for the stats and recorder checks. hypridle owns a bus
# name while it runs, so one dbus-monitor on that name replaces the poll.
check "the keep-awake button has no timer" \
  "$(grep -c 'Timer {' "$BAR_DIR/bar/AwakeButton.qml")" "0"
check "and hypridle is watched over the bus, in one place" \
  "$(grep -c 'command: \["dbus-monitor"' "$BAR_DIR/system/Idle.qml")" "1"
check "which runs a check only when the name changes hands" \
  "$(grep -c 'NameOwnerChanged.*root.check()' "$BAR_DIR/system/Idle.qml")" "1"
check "stats, idle and the recorder check are made once, in the shell" \
  "$(grep -c -E '^ *(Stats|Idle) \{|id: recorderCheck' "$BAR_DIR/shell.qml")" "3"
check "and not once per bar" \
  "$(grep -c -E '^ *(Stats|Idle) \{|id: recorderCheck' "$BAR_DIR/bar/Bar.qml")" "0"

# With two monitors, each bar had its own open panel and its own launch counts.
check "one panel at a time across monitors: the shell knows which bar has it" \
  "$(grep -c 'readonly property var panelOwner' "$BAR_DIR/shell.qml")" "1"
check "and a bar opening one closes the others" \
  "$(grep -c 'onOpened: opener => root.closeOthers(opener)' "$BAR_DIR/shell.qml")" "1"
check "and every bar catches clicks for a panel on another screen" \
  "$(grep -c 'OtherScreenCatcher { bar: bar }' "$BAR_DIR/bar/Bar.qml")" "1"
check "launch counts are one singleton" \
  "$(grep -c '^pragma Singleton' "$BAR_DIR/launcher/Launches.qml")" "1"
check "and the launcher keeps none of its own" \
  "$(grep -c 'launchesFile\|property var launches' "$BAR_DIR/panels/LauncherPanel.qml")" "0"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
