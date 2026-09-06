#!/bin/bash
# Four keybound toggles that no suite had ever run. Two of them parsed hyprctl
# output with a pattern hyprctl does not emit, and both failures were silent.
#
# monitor-mirror-toggle.sh asked whether the external display was already
# mirroring by grepping for "mirror of eDP-1". hyprctl writes "mirrorOf: eDP-1",
# 23 lines into the block, so `grep -A 5` could not have reached it even with
# the right words. is_mirrored was therefore always false and SUPER+SHIFT+M
# only ever turned mirroring on, never off.
#
# live-wallpaper-toggle.sh asked hyprpaper which wallpaper was on screen so
# that switching live mode off would freeze on that one. hyprpaper answers
# "eDP-1: /path"; the script stripped up to an "=" that is not there, kept the
# "eDP-1: " prefix, failed its own -f check and fell back to the stale cache.
# The freeze-on-what-you-see behaviour never once happened.
#
# The fixtures under fixtures/hyprctl are captured from a live Hyprland session
# rather than written from memory. monitors-mirrored.txt is trimmed to keep it
# short, so mirrorOf sits 10 lines into the block there instead of 23; that is
# still past the `grep -A 5` window the old code used.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
FIX="$REPO/test/fixtures/hyprctl"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"

# One hyprctl stub for every script here. It answers from files the test names,
# so a case is set up by pointing at a fixture rather than by editing the stub.
# `keyword` answers the way Hyprland answers a lua config, which is by refusing.
# The old stub returned 0 for every unmatched call, so `hyprctl keyword monitor`
# looked like it worked here while failing on every real install, and these
# checks passed against a script that had never mirrored anything. A fixture
# that resembles the real thing without being it is the failure class
# suite-hygiene-test.sh exists for, and this is one.
cat >"$STUB/hyprctl" <<'STUBEOF'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
  "monitors -j") cat "$MONITORS_JSON" ;;
  "monitors") cat "$MONITORS_TXT" ;;
  "hyprpaper listactive") cat "$LISTACTIVE" ;;
  keyword*) echo "keyword can't work with non-legacy parsers. Use eval." ;;
  eval*) printf '%s\n' "${HYPRCTL_EVAL_REPLY:-ok}" ;;
  *) exit 0 ;;
esac
STUBEOF
for tool in notify-send systemctl pactl wpctl pgrep pkill wl-mirror; do
  cat >"$STUB/$tool" <<STUBEOF
#!/bin/bash
printf '%s %s\n' "$tool" "\$*" >>"\$CALL_LOG"
exit "\${${tool//-/_}_RC:-0}"
STUBEOF
done
chmod +x "$STUB"/*

run() { CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" bash "$@"; }

# --- monitor-mirror-toggle.sh -----------------------------------------------

mirrored() { MONITORS_JSON="$FIX/monitors-mirrored.json" MONITORS_TXT="$FIX/monitors-mirrored.txt"; }
extended() { MONITORS_JSON="$FIX/monitors-extended.json" MONITORS_TXT="$FIX/monitors-mirrored.txt"; }
MIRROR_FLAG="$TMP/monitor_mirror_enabled"
mirror_run() {
  : >"$LOG"
  CALL_LOG="$LOG" MONITORS_JSON="$MONITORS_JSON" MONITORS_TXT="$MONITORS_TXT" \
    HYPRCTL_EVAL_REPLY="${HYPRCTL_EVAL_REPLY:-ok}" HYPRSIMPLE_MIRROR_FLAG="$MIRROR_FLAG" \
    PATH="$STUB:/usr/bin:/bin" bash "$BIN/monitor-mirror-toggle.sh" "$@" >/dev/null 2>&1
}
flag_state() { [[ -f $MIRROR_FLAG ]] && echo set || echo clear; }

# The call has to be eval. Hyprland refuses `keyword` outright when the config
# is lua, which hyprsimple's has been since the config split, so every one of
# these used to be issued and rejected while the script announced success.
mirrored; mirror_run toggle
check "an already mirrored display toggles back to extended" \
  "$(grep -c 'eval hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 1 })' "$LOG")" "1"
check "and does not ask for a mirror while doing it" \
  "$(grep -c 'mirror = ' "$LOG")" "0"

extended; mirror_run toggle
check "an extended display toggles into mirror" \
  "$(grep -c 'eval hl.monitor({ output = "HDMI-A-1", mode = "preferred", position = "auto", scale = 1, mirror = "eDP-1" })' "$LOG")" "1"

check "and never uses keyword, which this config cannot accept" \
  "$(grep -c 'hyprctl keyword' "$LOG")" "0"

# The two forced modes must ignore the current state entirely.
mirrored; mirror_run on
check "on forces mirror even when already mirrored" \
  "$(grep -c 'mirror = "eDP-1"' "$LOG")" "1"

# --- quiet has to be quiet ---------------------------------------------------
#
# It suppressed the two error notifications and neither of the success ones, so
# the hotplug handler it exists for would have popped a notification on every
# plug.
extended; mirror_run on
check "a keypress says what it did" "$(grep -c '^notify-send' "$LOG")" "1"
extended; mirror_run on quiet
check "and quiet says nothing at all" "$(grep -c '^notify-send' "$LOG")" "0"
check "while still making the change" "$(grep -c 'eval hl.monitor' "$LOG")" "1"
extended; mirror_run toggle quiet
check "quiet covers the toggle path too" "$(grep -c '^notify-send' "$LOG")" "0"

# --- a refusal is reported, not announced as success -------------------------

extended
HYPRCTL_EVAL_REPLY="some error from hyprland" mirror_run on
check "a rejected change does not claim mirror mode is on" \
  "$(grep -c 'Mirror mode enabled' "$LOG")" "0"
check "and says so instead" \
  "$(grep -c 'Hyprland rejected the change' "$LOG")" "1"
unset HYPRCTL_EVAL_REPLY

# --- the hotplug handler that makes on and quiet reachable -------------------
#
# monitor-mirror-toggle.sh documented this handler as its caller from the day
# on|off|quiet were added, and it was never written, so a projector did nothing
# until a keypress.
AUTOSTART="$REPO/default/hypr/autostart.lua"
check "autostart registers a monitor.added handler" \
  "$(grep -c 'hl.on("monitor.added"' "$AUTOSTART")" "1"
check "and it runs the mirror script quietly" \
  "$(grep -c 'mirror_script .. " on quiet"' "$AUTOSTART")" "1"

# --- mirroring survives a config reload --------------------------------------
#
# hyprctl eval sets a monitor at runtime, and a reload re-runs monitors.lua,
# whose hl.monitor call covers every output, so the mirror was dropped.
# theme-switcher.sh reloads on every theme switch, which un-mirrored a
# projector mid-presentation and said nothing.

rm -f "$MIRROR_FLAG"
extended; mirror_run restore
check "restore does nothing when mirroring was never asked for" \
  "$(grep -c 'eval hl.monitor' "$LOG")" "0"
check "and leaves the flag alone" "$(flag_state)" "clear"

extended; mirror_run on quiet
check "asking for mirroring records that it was asked for" "$(flag_state)" "set"

extended; mirror_run restore
check "so a reload re-applies it" \
  "$(grep -c 'mirror = "eDP-1"' "$LOG")" "1"
check "without saying anything, a reload not being a keypress" \
  "$(grep -c '^notify-send' "$LOG")" "0"

extended; mirror_run off quiet
check "turning it off forgets it" "$(flag_state)" "clear"
extended; mirror_run restore
check "and a later reload leaves the display extended" \
  "$(grep -c 'eval hl.monitor' "$LOG")" "0"

# --- unplugging forgets the request ------------------------------------------
#
# Otherwise the next reload tries to mirror onto a monitor that is not there.

extended; mirror_run on quiet
mirrored; mirror_run recover
check "recover keeps the request while the display is still connected" \
  "$(flag_state)" "set"

MONITORS_JSON="$FIX/monitors-internal-only.json" MONITORS_TXT="$FIX/monitors-mirrored.txt"
mirror_run recover
check "and drops it once the display has gone" "$(flag_state)" "clear"
check "while changing nothing about the remaining display" \
  "$(grep -c 'eval hl.monitor' "$LOG")" "0"

check "autostart registers the reload and removal handlers too" \
  "$(grep -cE 'hl.on\("(config.reloaded|monitor.removed)"' "$AUTOSTART")" "2"
check "and wires them to restore and recover" \
  "$(grep -cE 'mirror_script \.\. " (restore|recover)"' "$AUTOSTART")" "2"

# An unknown mode is still refused, now that there are five of them.
extended
mirror_run sideways
check "an unknown mode exits non-zero rather than doing something" \
  "$( CALL_LOG=$LOG MONITORS_JSON=$MONITORS_JSON MONITORS_TXT=$MONITORS_TXT \
      HYPRSIMPLE_MIRROR_FLAG=$MIRROR_FLAG PATH="$STUB:/usr/bin:/bin" \
      bash "$BIN/monitor-mirror-toggle.sh" sideways >/dev/null 2>&1; echo $? )" "2"

# --- live-wallpaper-toggle.sh -----------------------------------------------

# A theme with two backgrounds, the cache pointing at the first, hyprpaper
# showing the second. Turning live mode off must keep the one on screen.
HOME_DIR="$TMP/home"
THEME="$HOME_DIR/.config/hypr/themes/rosepine"
mkdir -p "$THEME/backgrounds" "$HOME_DIR/.cache" "$HOME_DIR/.local/bin"
cp "$BIN/hypr-helpers.sh" "$HOME_DIR/.local/bin/"
printf 'first\n' >"$THEME/backgrounds/0-with-you.jpg"
printf 'second\n' >"$THEME/backgrounds/1-elsewhere.jpg"
printf '%s\n' "$THEME/backgrounds/0-with-you.jpg" >"$HOME_DIR/.cache/current_wallpaper_path"
touch "$HOME_DIR/.cache/live_wallpaper_enabled"

printf 'eDP-1: %s\n' "$THEME/backgrounds/1-elsewhere.jpg" >"$TMP/listactive.txt"

: >"$LOG"
HOME="$HOME_DIR" LISTACTIVE="$TMP/listactive.txt" \
  MONITORS_JSON="$FIX/monitors-extended.json" MONITORS_TXT="$FIX/monitors-mirrored.txt" \
  run "$BIN/live-wallpaper-toggle.sh" off >/dev/null 2>&1
check "turning live wallpaper off keeps the one hyprpaper is showing" \
  "$(cat "$HOME_DIR/.cache/current_wallpaper_path")" "$THEME/backgrounds/1-elsewhere.jpg"
check "and copies that same file into the cache" \
  "$(cat "$HOME_DIR/.cache/current_wallpaper")" "second"
check "and clears the enabled flag" \
  "$([[ -e $HOME_DIR/.cache/live_wallpaper_enabled ]] && echo present || echo gone)" "gone"

# A path outside the theme is still rejected, so the parse fix did not remove
# the validation that keeps a stray answer from being cached.
printf 'eDP-1: /etc/passwd\n' >"$TMP/listactive.txt"
printf '%s\n' "$THEME/backgrounds/0-with-you.jpg" >"$HOME_DIR/.cache/current_wallpaper_path"
touch "$HOME_DIR/.cache/live_wallpaper_enabled"
: >"$LOG"
HOME="$HOME_DIR" LISTACTIVE="$TMP/listactive.txt" \
  MONITORS_JSON="$FIX/monitors-extended.json" MONITORS_TXT="$FIX/monitors-mirrored.txt" \
  run "$BIN/live-wallpaper-toggle.sh" off >/dev/null 2>&1
check "a path outside the theme falls back to the cached wallpaper" \
  "$(cat "$HOME_DIR/.cache/current_wallpaper_path")" "$THEME/backgrounds/0-with-you.jpg"

# --- audio-switch.sh --------------------------------------------------------

one_sink='[{"name":"alsa_output.analog-stereo","description":"Built-in Audio","ports":[]}]'
two_sinks='[{"name":"alsa_output.analog-stereo","description":"Built-in Audio","ports":[]},{"name":"bluez_output.AA","description":"Headphones","ports":[]}]'

cat >"$STUB/pactl" <<'STUBEOF'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$CALL_LOG"
case "$1" in
  get-default-sink) printf '%s\n' "$DEFAULT_SINK" ;;
  -f) printf '%s\n' "$SINKS_JSON" ;;
esac
STUBEOF
chmod +x "$STUB/pactl"

: >"$LOG"
SINKS_JSON="$one_sink" DEFAULT_SINK="alsa_output.analog-stereo" \
  run "$BIN/audio-switch.sh" >/dev/null 2>&1
check "a single sink sets no default" "$(grep -c 'set-default-sink' "$LOG")" "0"
check "and says so instead of claiming a switch" \
  "$(grep -c 'Only one audio output' "$LOG")" "1"
check "and never says Switched to" "$(grep -c 'Switched to' "$LOG")" "0"

: >"$LOG"
SINKS_JSON="$two_sinks" DEFAULT_SINK="alsa_output.analog-stereo" \
  run "$BIN/audio-switch.sh" >/dev/null 2>&1
check "two sinks still cycle to the other one" \
  "$(grep -c 'set-default-sink bluez_output.AA' "$LOG")" "1"
check "and report the switch" "$(grep -c 'Switched to: Headphones' "$LOG")" "1"

# --- virtual-mirror-toggle.sh -----------------------------------------------

# A PATH that genuinely lacks wl-mirror. Dropping the stub is not enough on a
# machine that has the real one in /usr/bin, which is how the first version of
# this check passed while proving nothing.
BARE="$TMP/bare"; mkdir -p "$BARE"
cp "$STUB"/* "$BARE/"
rm -f "$BARE/wl-mirror"
for real in bash jq; do ln -sf "$(command -v "$real")" "$BARE/$real"; done
if [[ -x $BARE/wl-mirror ]] || PATH="$BARE" command -v wl-mirror >/dev/null; then
  printf 'not ok - the bare PATH still finds wl-mirror, so the next checks prove nothing\n' >&2
  failures=$((failures + 1))
fi

: >"$LOG"
CALL_LOG="$LOG" MONITORS_JSON="$FIX/monitors-extended.json" \
  PATH="$BARE" bash "$BIN/virtual-mirror-toggle.sh" >/dev/null 2>&1
rc=$?
check "a missing wl-mirror exits non-zero" "$rc" "1"
check "and does not announce a mirror that never started" \
  "$(grep -c 'Mirroring' "$LOG")" "0"
check "and says what is missing" \
  "$(grep -c 'wl-mirror is not installed' "$LOG")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
