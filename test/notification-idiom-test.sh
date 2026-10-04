#!/bin/bash
# hyprsimple sent notifications two ways, notify-send and dunstify, with no rule
# saying which. This suite pins the single idiom, and the one behaviour that is
# easy to break silently: volume and brightness replace their own previous
# notification rather than stacking.

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

# Dismissing is the bar's to do, since it is what shows them.
check "notification-dismiss.sh asks the bar to dismiss them" \
  "$(grep -c 'ipc call bar dismissNotifications' "$REPO/.local/bin/notification-dismiss.sh")" "1"
check "and no script calls dunstctl" \
  "$(grep -rlE '(^|[^[:alnum:]_-])dunstctl' "$REPO/.local/bin/" | wc -l | tr -d ' ')" "0"

# Every notification these two send has to take the place of the last one, so a
# run of key presses does not stack a column of them up. They say so with the
# synchronous hint, which the bar matches on. Replacing by id does not work: the
# id a script makes up is not one the bar ever gave out.
#
# Counted against how many they send rather than pinned to a number. The
# numbers were 2 and 1, and adding a notification for "could not read the
# level" made them 3 and 2, so a check meant to be about the idiom failed on a
# change that obeyed it.
for notifier in volume-notify.sh brightness-notify.sh; do
  script="$REPO/.local/bin/$notifier"
  sends=$(grep -c 'notify-send' "$script")
  tagged=$(grep -c 'notify-send .*"\${SAME\[@\]}"' "$script")
  if (( sends < 2 )); then
    fail "$notifier sends $sends notifications, which is fewer than it has"
  else
    check "every notification $notifier sends takes the place of the last" "$tagged" "$sends"
  fi
  check "$notifier names what it replaces with the synchronous hint" \
    "$(grep -c '^SAME=(-h string:x-canonical-private-synchronous:[a-z]*)$' "$script")" "1"
done
check "and the bar matches on that hint" \
  "$(grep -c 'x-canonical-private-synchronous' "$REPO/default/quickshell/notifications/Notifications.qml")" "1"

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
#
# pactl, wf-recorder and wl-screenrec are here for a second reason. This suite
# runs screen-record.sh in internal-audio mode, and used to get no further than
# "No monitor source found" because the monitor lookup went through pw-cli,
# stubbed below, and the lookup was broken anyway. When that lookup was fixed to
# use pactl, the real pactl answered, the real wf-recorder started, and this
# suite recorded the screen three times per sweep. A suite that runs
# screen-record.sh must not be able to reach a real recorder, whatever the
# script does next.
#
# qs is here for a third. screen-record.sh tells the bar whether a recording is
# running, over the bar's ipc. This suite makes pgrep say one is, to reach the
# stop path, so the script reported a recording to the real bar of whoever ran
# the tests, and its indicator stayed lit with nothing recording.
for tool in wpctl brightnessctl hyprshot pkill upower pw-cli slurp pactl \
  wf-recorder wl-screenrec qs; do
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
# The real qs must be out of reach while it does, see the stubs above.
check "this suite cannot reach the real bar" \
  "$(PATH="$STUB:$PATH" command -v qs)" "$STUB/qs"
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
# Both state files under this suite's own temp directory. These used to be
# left at their real paths, so running the suite deleted the live notification
# flag and left a bogus brightness record for the next charge to restore.
: >"$LOG"
NOTIFY_LOG="$LOG" PATH="$STUB:$PATH" \
  HYPRSIMPLE_BATTERY_FLAG="$STUB/battery-flag" \
  HYPRSIMPLE_BRIGHTNESS_FILE="$STUB/battery-record" \
  bash "$BIN/battery-monitor.sh" >/dev/null 2>&1
check "battery-monitor reaches its low battery notification" \
  "$( (( $(grep -c 'Battery Low' "$LOG") >= 1 )) && echo reached )" "reached"

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

# What the bar does with the hint, replacing in place, is the bar's own
# behaviour and is not exercised here: it needs a running notification server.

# --- a level that could not be read is said, not invented ---------------------
#
# brightness-notify.sh divided by `brightnessctl max` without looking at it. On
# a machine brightnessctl has no device on, both reads come back empty and bash
# reported "division by 0" on stderr, where a keybind sends it nowhere, then
# showed "Brightness: %" with an empty bar.
#
# volume-notify.sh piped wpctl's output through awk, which prints 0 for a line
# it cannot parse, so a failed read showed "Volume: 0%": a specific, wrong
# number rather than a sign that nothing was read.
#
# The keybinds run each after a set that succeeded, so this is reached by
# running the script directly, which the README documents, and by the default
# sink going between the two calls, which is what a bluetooth headset
# disconnecting looks like.

FAILBIN="$STUB/failbin"; mkdir -p "$FAILBIN"
printf '#!/bin/bash\nexit 1\n' >"$FAILBIN/brightnessctl"
printf '#!/bin/bash\nexit 1\n' >"$FAILBIN/wpctl"
cat >"$FAILBIN/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUBEOF
chmod +x "$FAILBIN"/*

run_failing() {
  : >"$LOG"
  NOTIFY_LOG="$LOG" PATH="$FAILBIN:/usr/bin:/bin" bash "$BIN/$1" >"$STUB/stderr" 2>&1
  printf '%s' "$?" >"$STUB/rc"
}

run_failing brightness-notify.sh
check "brightness-notify says it could not read rather than showing a bar" \
  "$(grep -c 'Could not read the current brightness' "$LOG")" "1"
check "and shows no percentage at all" \
  "$(grep -c 'Brightness: ' "$LOG")" "0"
check "and prints no shell error" \
  "$(grep -ci 'division by 0\|error token' "$STUB/stderr")" "0"
check "and exits non-zero" \
  "$([[ $(cat "$STUB/rc") != "0" ]] && echo nonzero || echo zero)" "nonzero"

run_failing volume-notify.sh
check "volume-notify says it could not read rather than claiming a level" \
  "$(grep -c 'Could not read the current volume' "$LOG")" "1"
check "and does not report zero, which is a real level it did not measure" \
  "$(grep -c 'Volume: 0%' "$LOG")" "0"
check "and exits non-zero" \
  "$([[ $(cat "$STUB/rc") != "0" ]] && echo nonzero || echo zero)" "nonzero"

# The case the exit status does not cover, which is the one that reaches a
# user. `wpctl get-volume` on a node that is gone exits 0 and prints
#
#   Node '@DEFAULT_AUDIO_SINK@' not found
#
# on stdout, measured directly. The old parse was `awk '{print int($2*100)}'`,
# which took $2 of that line and printed 0, so the notification said
# "Volume: 0%" about a sink that was not there. A bluetooth headset
# disconnecting between the set and the get looks exactly like this.
GONEBIN="$STUB/gonebin"; mkdir -p "$GONEBIN"
cp "$FAILBIN/notify-send" "$GONEBIN/notify-send"
cat >"$GONEBIN/wpctl" <<'STUBEOF'
#!/bin/bash
echo "Node '@DEFAULT_AUDIO_SINK@' not found"
exit 0
STUBEOF
chmod +x "$GONEBIN"/*

: >"$LOG"
NOTIFY_LOG="$LOG" PATH="$GONEBIN:/usr/bin:/bin" bash "$BIN/volume-notify.sh" >/dev/null 2>&1
check "a sink that answers without a volume is not reported as zero" \
  "$(grep -c 'Volume: 0%' "$LOG")" "0"
check "and is reported as unreadable instead" \
  "$(grep -c 'Could not read the current volume' "$LOG")" "1"

# Anti-vacuity: with readers that answer, both still report the level. A script
# that always said "could not read" would satisfy every check above.
OKBIN="$STUB/okbin"; mkdir -p "$OKBIN"
cp "$FAILBIN/notify-send" "$OKBIN/notify-send"
printf '#!/bin/bash\n[[ $1 == get ]] && echo 30\n[[ $1 == max ]] && echo 100\nexit 0\n' >"$OKBIN/brightnessctl"
printf '#!/bin/bash\necho "Volume: 0.55"\n' >"$OKBIN/wpctl"
chmod +x "$OKBIN"/*

: >"$LOG"
NOTIFY_LOG="$LOG" PATH="$OKBIN:/usr/bin:/bin" bash "$BIN/brightness-notify.sh" >/dev/null 2>&1
check "a readable brightness is still reported" "$(grep -c 'Brightness: 30%' "$LOG")" "1"

: >"$LOG"
NOTIFY_LOG="$LOG" PATH="$OKBIN:/usr/bin:/bin" bash "$BIN/volume-notify.sh" >/dev/null 2>&1
check "a readable volume is still reported" "$(grep -c 'Volume: 55%' "$LOG")" "1"

printf '#!/bin/bash\necho "Volume: 0.42 [MUTED]"\n' >"$OKBIN/wpctl"
: >"$LOG"
NOTIFY_LOG="$LOG" PATH="$OKBIN:/usr/bin:/bin" bash "$BIN/volume-notify.sh" >/dev/null 2>&1
check "and muted is still reported as muted, not as a level" \
  "$(grep -c 'Muted' "$LOG")" "1"

# A volume of nought is a real reading and must still be shown as one.
printf '#!/bin/bash\necho "Volume: 0.00"\n' >"$OKBIN/wpctl"
: >"$LOG"
NOTIFY_LOG="$LOG" PATH="$OKBIN:/usr/bin:/bin" bash "$BIN/volume-notify.sh" >/dev/null 2>&1
check "a genuine zero volume is still shown, not treated as unreadable" \
  "$(grep -c 'Volume: 0%' "$LOG")" "1"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
