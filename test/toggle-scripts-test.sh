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
# A rofi that answers with nothing, never the real one. These scripts open a
# picker when given no argument and /usr/bin is on the PATH below, so the real
# rofi was reachable from here. It reached the maintainer's screen once, from a
# suite that had no stub, and opened a window complaining about a theme inside
# the fixture.
printf '#!/bin/bash\nexit 1\n' >"$STUB/rofi"
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

run() { CALL_LOG="$LOG" MIRROR_PIDS="${MIRROR_PIDS:-/dev/null}" PATH="$STUB:/usr/bin:/bin" bash "$@"; }

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
# hyprsimple-require.sh too: the scripts test for their helpers before
# sourcing them, so a fixture without it stops rather than running.
cp "$BIN/hypr-helpers.sh" "$BIN/hyprsimple-require.sh" "$HOME_DIR/.local/bin/"
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

# set-default-sink can be made to fail, because it can fail in life: the list
# the choice came from is a moment old, and pactl exits 1 with "Failure: No
# such entity" for a sink that has gone since. A bluetooth headset
# disconnecting in between looks exactly like that.
cat >"$STUB/pactl" <<'STUBEOF'
#!/bin/bash
printf 'pactl %s\n' "$*" >>"$CALL_LOG"
case "$1" in
  get-default-sink) printf '%s\n' "$DEFAULT_SINK" ;;
  -f) printf '%s\n' "$SINKS_JSON" ;;
  set-default-sink)
    if [[ -n ${SET_SINK_FAILS:-} ]]; then
      echo "Failure: No such entity" >&2
      exit 1
    fi
    ;;
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

# The sink goes between the list and the set. pactl fails, and the switch used
# to be announced anyway: sound still coming out of the speakers while the
# notification said it had moved. Same shape as the single-sink case above,
# which this file already covers.
: >"$LOG"
SET_SINK_FAILS=1 SINKS_JSON="$two_sinks" DEFAULT_SINK="alsa_output.analog-stereo" \
  run "$BIN/audio-switch.sh" >/dev/null 2>&1
check "a switch pactl refused is not reported as done" \
  "$(grep -c 'Switched to' "$LOG")" "0"
check "and is reported as failed instead" \
  "$(grep -c 'Could not switch to Headphones' "$LOG")" "1"
check "critically, so it is not lost among the ordinary notifications" \
  "$(grep -c -- '-u critical' "$LOG")" "1"

# It was still attempted, or the checks above would pass for a script that
# stopped trying to switch at all.
check "and the switch really was attempted" \
  "$(grep -c 'set-default-sink bluez_output.AA' "$LOG")" "1"

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

# The mirror is announced only when wl-mirror is still there to be selected.
#
# wl-mirror is backgrounded, so a refused output or a missing protocol ends it
# at once and silently. The notification told the user to go and select a window
# that was never opened, which is worse than saying nothing: the whole point of
# this key is that the window exists to be shared. screen-record.sh was fixed
# for the same shape and this was not.
#
# The stub wl-mirror exits immediately, which is exactly the failing case, so a
# separate one that stays up is needed for the working case.
#
# pgrep_RC=1 throughout, or the stub reports wl-mirror already running and the
# script takes its stop branch without reaching any of this.
# It records its own pid, so the cleanup below can name it.
#
# The first version cleaned up with `pkill -f wl-mirror-alive`, and pkill -f
# matches any process whose whole command line contains that string. It killed
# the shell that was running this suite, because that shell's command line
# contained the pattern. Killing one recorded pid cannot reach anything else.
cat >"$STUB/wl-mirror-alive" <<'STUBEOF'
#!/bin/bash
printf 'wl-mirror %s\n' "$*" >>"$CALL_LOG"
printf '%s\n' "$$" >>"$MIRROR_PIDS"
exec sleep 5
STUBEOF
chmod +x "$STUB/wl-mirror-alive"

MIRROR_PIDS="$TMP/mirror-pids"; : >"$MIRROR_PIDS"
kill_mirrors() {
  local pid
  while read -r pid; do
    [[ -n $pid ]] && kill "$pid" 2>/dev/null
  done <"$MIRROR_PIDS"
  : >"$MIRROR_PIDS"
}

: >"$LOG"
MONITORS_JSON="$FIX/monitors-extended.json" pgrep_RC=1 HYPRSIMPLE_MIRROR_START_WAIT=0.1 \
  run "$BIN/virtual-mirror-toggle.sh" >/dev/null 2>&1
rc=$?
check "a wl-mirror that dies at once is not announced as mirroring" \
  "$(grep -c 'Mirroring' "$LOG")" "0"
check "and the failure is reported" \
  "$(grep -c 'could not mirror' "$LOG")" "1"
check "and the script exits non-zero" "$rc" "1"

# The working case, with a wl-mirror that stays up.
cp "$STUB/wl-mirror-alive" "$STUB/wl-mirror"
: >"$LOG"
MONITORS_JSON="$FIX/monitors-extended.json" pgrep_RC=1 HYPRSIMPLE_MIRROR_START_WAIT=0.2 \
  run "$BIN/virtual-mirror-toggle.sh" >/dev/null 2>&1
rc=$?
check "a wl-mirror that stays up is announced" \
  "$(grep -c 'Mirroring' "$LOG")" "1"
check "and names the monitor it was given" \
  "$(grep -c 'Mirroring eDP-1' "$LOG")" "1"
check "and exits 0" "$rc" "0"
# Left running by the check above, and this suite must not leak it.
kill_mirrors

# A compositor that answers with no focused monitor gave an empty name, and
# "Mirroring  - Select this window" was shown with a blank in it.
cat >"$TMP/monitors-none-focused.json" <<'JSONEOF'
[{"name":"eDP-1","focused":false}]
JSONEOF
: >"$LOG"
MONITORS_JSON="$TMP/monitors-none-focused.json" pgrep_RC=1 HYPRSIMPLE_MIRROR_START_WAIT=0.1 \
  run "$BIN/virtual-mirror-toggle.sh" >/dev/null 2>&1
rc=$?
check "no focused monitor is reported rather than mirrored" \
  "$(grep -c 'Could not tell which monitor is focused' "$LOG")" "1"
check "and nothing is announced as mirroring" \
  "$(grep -c 'Mirroring' "$LOG")" "0"
check "and wl-mirror is never run" "$(grep -c '^wl-mirror ' "$LOG")" "0"
check "and the script exits non-zero" "$rc" "1"

# --- toggle-idle.sh ----------------------------------------------------------
#
# It backgrounded hypridle, discarded its output and notified regardless, so a
# hypridle that refused to start left the user told the screen would lock on
# idle when nothing was going to lock it. Worse than the other
# announce-regardless bugs here: the rest waste a keypress, this one says a
# screen lock is armed when it is not.
#
# Its own stub directory, because pgrep has to answer differently before and
# after the start, which the shared stub cannot do.
IDLE="$TMP/idle"; mkdir -p "$IDLE"
IDLE_STARTED="$IDLE/started"

cat >"$IDLE/notify-send" <<'STUBEOF'
#!/bin/bash
printf 'notify-send %s\n' "$*" >>"$CALL_LOG"
STUBEOF
cat >"$IDLE/pgrep" <<'STUBEOF'
#!/bin/bash
[[ -e $IDLE_STARTED ]] && exit 0
exit 1
STUBEOF
cat >"$IDLE/uwsm" <<'STUBEOF'
#!/bin/bash
printf 'uwsm %s\n' "$*" >>"$CALL_LOG"
[[ -n ${UWSM_FAILS:-} ]] && exit 1
: >"$IDLE_STARTED"
exit 0
STUBEOF
cat >"$IDLE/pkill" <<'STUBEOF'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$CALL_LOG"
[[ -n ${PKILL_FAILS:-} ]] && exit 1
rm -f "$IDLE_STARTED"
exit 0
STUBEOF
chmod +x "$IDLE"/*

run_idle() {
  CALL_LOG="$LOG" IDLE_STARTED="$IDLE_STARTED" HYPRSIMPLE_IDLE_START_WAIT=0.1 \
    PATH="$IDLE:/usr/bin:/bin" bash "$BIN/toggle-idle.sh" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/idle-rc"
}

# hypridle refuses to start.
rm -f "$IDLE_STARTED"; : >"$LOG"
UWSM_FAILS=1 run_idle
check "a hypridle that will not start is not reported as locking" \
  "$(grep -c 'Now locking when idle' "$LOG")" "0"
check "and the user is told the screen will not lock" \
  "$(grep -c 'will not lock when idle' "$LOG")" "1"
check "critically, because a lock that is not armed is worth interrupting for" \
  "$(grep -c -- '-u critical' "$LOG")" "1"
check "and the script exits non-zero" \
  "$([[ $(cat "$TMP/idle-rc") != "0" ]] && echo nonzero || echo zero)" "nonzero"
check "and it really did try to start it" "$(grep -c '^uwsm ' "$LOG")" "1"

# hypridle starts and stays up.
rm -f "$IDLE_STARTED"; : >"$LOG"
run_idle
check "a hypridle that starts is reported as locking" \
  "$(grep -c 'Now locking when idle' "$LOG")" "1"
check "and the script exits 0" "$(cat "$TMP/idle-rc")" "0"

# Running again turns it off, because pgrep now finds it.
: >"$LOG"
run_idle
check "a second press stops it" "$(grep -c 'Stopped locking when idle' "$LOG")" "1"
check "and exits 0" "$(cat "$TMP/idle-rc")" "0"

# The stop can fail too, and then idle locking is still on.
: >"$IDLE_STARTED"; : >"$LOG"
PKILL_FAILS=1 run_idle
check "a stop that failed is not reported as stopped" \
  "$(grep -c 'Stopped locking when idle' "$LOG")" "0"
check "and says the screen still locks" \
  "$(grep -c 'still locks when idle' "$LOG")" "1"
check "and exits non-zero" \
  "$([[ $(cat "$TMP/idle-rc") != "0" ]] && echo nonzero || echo zero)" "nonzero"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
