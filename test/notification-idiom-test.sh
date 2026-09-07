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
#
# pactl, wf-recorder and wl-screenrec are here for a second reason. This suite
# runs screen-record.sh in internal-audio mode, and used to get no further than
# "No monitor source found" because the monitor lookup went through pw-cli,
# stubbed below, and the lookup was broken anyway. When that lookup was fixed to
# use pactl, the real pactl answered, the real wf-recorder started, and this
# suite recorded the screen three times per sweep. A suite that runs
# screen-record.sh must not be able to reach a real recorder, whatever the
# script does next.
for tool in wpctl brightnessctl hyprshot pkill upower pw-cli slurp pactl \
  wf-recorder wl-screenrec; do
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

# The behaviour itself, against the running daemon. Skipped loudly where dunst
# is not running, which includes CI. A check that silently degrades into a
# no-op on the runner reads as coverage while proving nothing.
# Gated on dunstctl actually answering, not on the binary existing and the
# process being alive. Both of those can be true while the session bus is
# unreachable, and then every check below returns an empty string and fails
# with a confusing message instead of skipping.
if dunstctl count displayed >/dev/null 2>&1; then
  # Every check below asks about notifications this suite sent, and about
  # nothing else on the machine.
  #
  # This section used to read `dunstctl count displayed`, which counts the whole
  # stack, so any notification from anything else that landed inside a window
  # was counted as this suite's. Reproduced deliberately rather than waited for:
  # with one unrelated notify-send 0.4s into the 1.5s window below, "a critical
  # notification honours its own -t" read 2 where it wanted 0. That is the flake
  # that showed up once in a full sweep and would not reproduce on its own.
  #
  # Two repairs were tried against a machine sending unrelated notifications
  # throughout the run, and both broke in their turn:
  #
  #   count displayed, differenced around a close by id
  #     a notification dunst had queued rather than shown read as absent. With
  #     30 standing, dunst had 19 displayed and 11 waiting.
  #   displayed plus waiting, differenced the same way
  #     the total moved between the two reads when something else arrived, so
  #     the difference came out as -1 rather than 0 or 1.
  #
  # Both measured the whole machine and subtracted. dunst offers no way to list
  # what it is holding, over dunstctl or over its D-Bus interface, so the two
  # questions here are asked in the two ways it does answer.

  # dunst moves a notification into its history the moment it expires or is
  # closed, and a live one is not there, so one read of one id says whether
  # dunst still holds it.
  held_by_id() {
    local seen
    seen=$(dunstctl history |
      jq --argjson i "$1" '[.data[][] | select(.id.data == $i)] | length')
    [[ $seen == 0 ]] && printf '1' || printf '0'
  }

  # How many notifications of one probe dunst is holding. History is the only
  # listable view, so the probes are closed into it and counted there by an
  # appname unique to this run and this check, which is what keeps everything
  # else on the machine out of the number.
  probe_app() { printf 'hyprsimple-probe-%s-%s' "$$" "$1"; }
  held_for_app() {
    dunstctl close-all
    dunstctl history |
      jq --arg a "$1" '[.data[][] | select(.appname.data == $a)] | length'
  }

  # History is a ring, so a long enough burst of other notifications pushes an
  # entry out of it and these reads would miss a probe that really was there.
  #
  # Detected rather than guessed at. A marker is closed into history before each
  # probe, so it sits older than anything the probe puts there, and eviction
  # takes the oldest first. A marker still present when the probe is read means
  # nothing of that age has been dropped and the reading stands. Checked against
  # dunst rather than against a number, so it does not go stale if
  # history_length is ever set.
  mark_history() {
    local id
    id=$(notify-send -p -u low -t 1000 --transient "probe" "history marker")
    dunstctl close "$id" >/dev/null 2>&1
    printf '%s' "$id"
  }
  marker_survives() {
    [[ $(dunstctl history |
      jq --argjson i "$1" '[.data[][] | select(.id.data == $i)] | length') != 0 ]]
  }
  # Said rather than reported as a product failure, in the same shape as the
  # timing guard further down.
  held_check() {
    local marker="$1"; shift
    if marker_survives "$marker"; then
      check "$1" "$2" "$3"
    else
      printf 'not ok - inconclusive: dunst evicted a marker from history, so a probe read may have missed one\n' >&2
      failures=$((failures + 1))
    fi
  }

  # The probes have to be able to fail, or every check below reads the same
  # number for a working dunst and a broken one.
  dunstctl close-all
  canary=$(notify-send -p -u low -t 5000 --transient "probe" "canary")
  check "a notification just sent reads as held" "$(held_by_id "$canary")" "1"
  dunstctl close "$canary" >/dev/null 2>&1
  check "and reads as gone once closed" "$(held_by_id "$canary")" "0"

  # --- one id replaces, two ids accumulate -----------------------------------

  app_r=$(probe_app replace)
  dunstctl close-all
  mark_r=$(mark_history)
  notify-send -a "$app_r" -u low -t 3000 -r 4242 --transient "probe" "first"
  notify-send -a "$app_r" -u low -t 3000 -r 4242 --transient "probe" "second"
  held_check "$mark_r" "two notify-send with one id leave dunst holding one notification" \
    "$(held_for_app "$app_r")" "1"

  # Discrimination: the check above is worthless unless the same pair without
  # -r would actually leave two.
  app_n=$(probe_app distinct)
  dunstctl close-all
  mark_n=$(mark_history)
  notify-send -a "$app_n" -u low -t 3000 --transient "probe" "first"
  notify-send -a "$app_n" -u low -t 3000 --transient "probe" "second"
  held_check "$mark_n" "the same pair without an id leaves it holding two" \
    "$(held_for_app "$app_n")" "2"

  # --- what dunst does with critical urgency ---------------------------------
  #
  # screen-record.sh sends critical notifications with -t 3000, and dunst
  # documents critical urgency as never expiring by default. It does expire
  # here, because default/dunst/10-hyprsimple.conf sets a global timeout and
  # the urgency_critical sections override only colours.
  #
  # Both probes are --transient, and that is not incidental. The same file sets
  # idle_threshold = 120, which stops notifications timing out at all once the
  # user has been idle that long. An automated run is idle by definition, so
  # without --transient these checks pass when someone is at the keyboard and
  # fail when nobody is, which is how they were written and how they flaked.
  # dunst documents transient as the client-side bypass for exactly this.
  #
  # Measured in the failing state rather than reasoned about: with the machine
  # idle, an ordinary -t 1000 notification was still displayed after 2 seconds
  # and a transient one was gone, at both critical and low urgency.
  #
  # The second races a wall clock against dunst's global timeout, so it reports
  # how long it actually took. If the elapsed time reaches the timeout the check
  # could not have concluded anything, and it says so.
  global_timeout_ms=5000
  elapsed_ms() { printf '%s' "$(( $(date +%s%3N) - $1 ))"; }

  dunstctl close-all
  mark_s=$(mark_history)
  short=$(notify-send -p -u critical -t 1000 --transient "probe" "critical honours -t")
  sleep 1.5
  held_check "$mark_s" "a critical notification honours its own -t" \
    "$(held_by_id "$short")" "0"

  dunstctl close-all
  mark_l=$(mark_history)
  started=$(date +%s%3N)
  long=$(notify-send -p -u critical --transient "probe" "critical without -t outlives it")
  sleep 1
  still_held=$(held_by_id "$long")
  took=$(elapsed_ms "$started")
  if (( took >= global_timeout_ms )); then
    printf 'not ok - inconclusive: reading the state took %sms, past the %sms timeout\n' \
      "$took" "$global_timeout_ms" >&2
    failures=$((failures + 1))
  else
    held_check "$mark_l" "a critical notification without -t outlives that window (${took}ms of ${global_timeout_ms}ms)" \
      "$still_held" "1"
  fi
  dunstctl close-all
else
  printf 'skip - dunst not running, replacement behaviour not exercised\n'
fi

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
