#!/bin/bash
# hyprsimple sent notifications two ways, notify-send and dunstify, with no rule
# saying which. This suite pins the single idiom, and the one behaviour the
# substitution could have broken silently: volume and brightness replace their
# own previous notification by id rather than stacking.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

check "no script calls dunstify" \
  "$(grep -rlE '(^|[^[:alnum:]_-])dunstify' "$REPO/.local/bin/" | wc -l | tr -d ' ')" "0"

# dunstctl is a different tool with no notify-send equivalent, so the check
# above must not become a blanket ban on everything dunst ships.
check "notification-dismiss.sh still uses dunstctl" \
  "$(grep -c 'dunstctl' "$REPO/.local/bin/notification-dismiss.sh")" "1"

# The replace-by-id sites, named so a future edit that drops -r shows up here
# rather than only on someone's screen.
check "volume-notify still replaces by id" \
  "$(grep -c -- '-r "\?\$NOTIFY_ID' "$REPO/.local/bin/volume-notify.sh")" "2"
check "brightness-notify still replaces by id" \
  "$(grep -c -- '-r "\?\$NOTIFY_ID' "$REPO/.local/bin/brightness-notify.sh")" "1"

# Each converted line, reached by running its own script rather than by
# replaying the command out of context. A stub notify-send first on PATH
# records every invocation, so the assertion is that the script's control flow
# actually gets there and composes something notify-send would accept.
#
# Replaying the composed command proves the flags parse. It cannot prove the
# line is reachable, or that the variables on it hold what the author assumed.

STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
LOG="$STUB/notifications"
: >"$LOG"

# Logs and nothing else. It deliberately does not validate its arguments:
# notify-send has no dry-run mode, so the only way to make it rule on a real
# argument list is to send the notification, which needs a running daemon and
# would put this suite's probes on the user's screen. Reachability is what is
# asserted here, and the live section below is what exercises the real binary.
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"${NOTIFY_LOG:?}"
STUBEOF
chmod +x "$STUB/notify-send"

# Stand-ins for the tools each script queries. None of them may notify.
for tool in wpctl brightnessctl hyprshot pkill upower pw-cli slurp; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$tool"
  chmod +x "$STUB/$tool"
done
# pgrep answers "is a recording already running". It must say no by default,
# or screen-record.sh short circuits to its stop path and the start-path
# branches below are never reached.
printf '#!/bin/bash\nexit 1\n' >"$STUB/pgrep"; chmod +x "$STUB/pgrep"
printf '#!/bin/bash\necho "Volume: 0.30"\n' >"$STUB/wpctl"
printf '#!/bin/bash\n[[ $1 == max ]] && echo 1000 || echo 500\n' >"$STUB/brightnessctl"
chmod +x "$STUB/wpctl" "$STUB/brightnessctl"

# Asserts on the notification's text, not on how many were sent. Counting was
# not enough: with pgrep stubbed to succeed, screen-record.sh took its stop
# path and sent one notification for every case, so three checks passed while
# never reaching the branch they named. Sabotage found it, a count never would.
run_script() {
  local label="$1" want="$2"; shift 2
  : >"$LOG"
  NOTIFY_LOG="$LOG" PATH="$STUB:$PATH" "$@" >/dev/null 2>&1
  check "$label" "$(grep -cF "$want" "$LOG")" "1"
}

BIN="$REPO/.local/bin"

run_script "volume-notify reaches its notification" "Volume" \
  bash "$BIN/volume-notify.sh"
run_script "brightness-notify reaches its notification" "Brightness" \
  bash "$BIN/brightness-notify.sh"
run_script "screenshot reaches its notification" "Screenshot" \
  bash "$BIN/screenshot.sh" clipboard
run_script "screen-record reports a missing output directory" "directory does not exist" \
  env XDG_VIDEOS_DIR="$STUB/definitely-not-here" bash "$BIN/screen-record.sh"
run_script "screen-record rejects an invalid audio mode" "Invalid audio mode" \
  env XDG_VIDEOS_DIR="$STUB" bash "$BIN/screen-record.sh" region bogus-mode
run_script "screen-record reports a missing monitor source" "No monitor source found" \
  env XDG_VIDEOS_DIR="$STUB" bash "$BIN/screen-record.sh" region internal

# The stop path needs a recording to appear active, so pgrep must succeed.
printf '#!/bin/bash\nexit 0\n' >"$STUB/pgrep"; chmod +x "$STUB/pgrep"
run_script "screen-record reports a saved recording" "Screen recording saved" \
  env XDG_VIDEOS_DIR="$STUB" bash "$BIN/screen-record.sh" stop
printf '#!/bin/bash\nexit 1\n' >"$STUB/pgrep"; chmod +x "$STUB/pgrep"

# battery-monitor notifies once per threshold, gated on a flag file, so the
# flag has to be absent for the notification to be the thing under test.
cat >"$STUB/upower" <<'STUBEOF'
#!/bin/bash
[[ $1 == -e ]] && { echo /org/freedesktop/UPower/devices/BAT0; exit 0; }
echo "    percentage:          9%"
echo "    state:               discharging"
STUBEOF
chmod +x "$STUB/upower"

# Asserting only that the line is reached, not how many times. A single 9%
# reading currently sends three identical notifications, because the loop
# visits every threshold at or above the level and the flag file only
# remembers the last one written. That is a real defect, it predates the
# notification substitution, and fixing it is a behaviour change this suite
# has no mandate for. Pinning the count here would pin the bug.
rm -f /tmp/battery-notification-flag
: >"$LOG"
NOTIFY_LOG="$LOG" PATH="$STUB:$PATH" bash "$BIN/battery-monitor.sh" >/dev/null 2>&1
check "battery-monitor reaches its low battery notification" \
  "$( (( $(grep -c 'Battery Low' "$LOG") >= 1 )) && echo reached )" "reached"
rm -f /tmp/battery-notification-flag

# capslock-notify polls a sysfs LED when one exists and falls back to hyprctl
# when it does not. This exercises the fallback, which is the path CI takes,
# since a runner has no capslock LED.
#
# On a machine that does have one, run the whole suite with the LED directory
# masked to reach it:
#
#   unshare -rm bash -c 'mount -t tmpfs none /sys/class/leds && exec bash test/notification-idiom-test.sh'
#
# No root needed, and it is how this check was verified before it shipped.
if compgen -G '/sys/class/leds/input*::capslock/brightness' >/dev/null; then
  printf 'skip - capslock LED present, mask /sys/class/leds to reach the fallback\n'
else
  # The counter path is baked in rather than passed through the environment.
  # `PATH=... STUB=...` in one command is a trap: the assignments are not
  # visible to each other, so it reads as though PATH sees the new STUB when
  # it does not.
  cat >"$STUB/hyprctl" <<EOF
#!/bin/bash
n=\$(cat "$STUB/caps" 2>/dev/null || echo 0)
echo \$((n + 1)) >"$STUB/caps"
[[ \$n == 0 ]] && echo false || echo true
EOF
  chmod +x "$STUB/hyprctl"
  printf '#!/bin/bash\ncat\n' >"$STUB/jq"; chmod +x "$STUB/jq"
  : >"$LOG"; echo 0 >"$STUB/caps"
  NOTIFY_LOG="$LOG" PATH="$STUB:$PATH" timeout 3 bash "$BIN/capslock-notify.sh" >/dev/null 2>&1
  check "capslock-notify reaches a notification when the state flips" \
    "$(grep -c 'Caps Lock' "$LOG")" "1"
fi

# The behaviour itself, against the running daemon. Skipped loudly where dunst
# is not running, which includes CI. A check that silently degrades into a
# no-op on the runner reads as coverage while proving nothing.
# Gated on dunstctl actually answering, not on the binary existing and the
# process being alive. Both of those can be true while the session bus is
# unreachable, and then every check below returns an empty string and fails
# with a confusing message instead of skipping.
if dunstctl count displayed >/dev/null 2>&1; then
  dunstctl close-all
  notify-send -u low -t 3000 -r 4242 "probe" "first"
  notify-send -u low -t 3000 -r 4242 "probe" "second"
  check "two notify-send with one id display as one notification" \
    "$(dunstctl count displayed)" "1"

  # Discrimination: the check above is worthless unless the same pair without
  # -r would actually display two.
  dunstctl close-all
  notify-send -u low -t 3000 "probe" "first"
  notify-send -u low -t 3000 "probe" "second"
  check "the same pair without an id displays as two" \
    "$(dunstctl count displayed)" "2"

  # screen-record.sh sends critical notifications with -t 3000, and dunst's
  # documented default for critical urgency is never to expire. It does expire
  # here, because hyprsimple's own dunst config sets a global timeout and the
  # urgency_critical section overrides only colours. Measured rather than
  # assumed: a critical notification with -t 1000 is gone after 2.5s, and one
  # with no -t survives that long. Asserting it so a drop-in that sets
  # urgency_critical timeout cannot change it invisibly.
  dunstctl close-all
  notify-send -u critical -t 1000 "probe" "critical honours -t"
  sleep 2.5
  check "a critical notification honours its own -t" \
    "$(dunstctl count displayed)" "0"

  dunstctl close-all
  notify-send -u critical "probe" "critical without -t outlives it"
  sleep 2.5
  check "a critical notification without -t outlives that window" \
    "$(dunstctl count displayed)" "1"
  dunstctl close-all
else
  printf 'skip - dunst not running, replacement behaviour not exercised\n'
fi

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
