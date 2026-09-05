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
cat >"$STUB/hyprctl" <<'STUBEOF'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
  "monitors -j") cat "$MONITORS_JSON" ;;
  "monitors") cat "$MONITORS_TXT" ;;
  "hyprpaper listactive") cat "$LISTACTIVE" ;;
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

: >"$LOG"
MONITORS_JSON="$FIX/monitors-mirrored.json" MONITORS_TXT="$FIX/monitors-mirrored.txt" \
  run "$BIN/monitor-mirror-toggle.sh" toggle >/dev/null 2>&1
check "an already mirrored display toggles back to extended" \
  "$(grep -c 'keyword monitor HDMI-A-1,preferred,auto,1$' "$LOG")" "1"
check "and does not re-issue the mirror keyword" \
  "$(grep -c 'mirror,eDP-1' "$LOG")" "0"

: >"$LOG"
MONITORS_JSON="$FIX/monitors-extended.json" MONITORS_TXT="$FIX/monitors-mirrored.txt" \
  run "$BIN/monitor-mirror-toggle.sh" toggle >/dev/null 2>&1
check "an extended display toggles into mirror" \
  "$(grep -c 'keyword monitor HDMI-A-1,preferred,auto,1,mirror,eDP-1' "$LOG")" "1"

# The two forced modes must ignore the current state entirely.
: >"$LOG"
MONITORS_JSON="$FIX/monitors-mirrored.json" MONITORS_TXT="$FIX/monitors-mirrored.txt" \
  run "$BIN/monitor-mirror-toggle.sh" on >/dev/null 2>&1
check "on forces mirror even when already mirrored" \
  "$(grep -c 'mirror,eDP-1' "$LOG")" "1"

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
