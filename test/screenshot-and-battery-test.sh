#!/bin/bash
# Three defects that shipped because nothing ran the code: an unquoted path in
# screenshot.sh, a misspelled hyprshot flag beside it, and a battery loop that
# sent one notification per threshold rather than one per crossing.
# Never invokes hyprshot, upower or brightnessctl for real.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
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

# Records one line per invocation: the argument count, then the arguments. The
# count is the point. An unquoted path containing a space arrives as two
# arguments and the count goes up, which is the defect, and no assertion on the
# text alone would see it.
cat >"$STUB/hyprshot" <<'STUBEOF'
#!/bin/bash
printf '%s|%s\n' "$#" "$*" >>"${CALL_LOG:?}"
STUBEOF
chmod +x "$STUB/hyprshot"
printf '#!/bin/bash\nexit 0\n' >"$STUB/notify-send"; chmod +x "$STUB/notify-send"

# A home directory with a space in it, which is what the quoting bug needs to
# show itself. Nothing here touches the real home.
SPACED="$TMP/home with space"
mkdir -p "$SPACED"

for mode in window region monitor; do
  : >"$LOG"
  CALL_LOG="$LOG" HOME="$SPACED" PATH="$STUB:$PATH" bash "$BIN/screenshot.sh" "$mode" >/dev/null 2>&1
  check "screenshot $mode passes the output folder as one argument" \
    "$(cut -d'|' -f1 <"$LOG")" "5"
done

# hyprshot documents -z, --freeze. screenshot.sh spent its whole life passing
# --freze, which getopt rejects while the screenshot proceeds unfrozen, so the
# one mode where freezing matters never froze.
check "no screenshot mode passes a flag hyprshot does not know" \
  "$(grep -c -- '--freze' "$BIN/screenshot.sh")" "0"
check "region freezes the screen" \
  "$(grep -c -- '-m region --freeze' "$BIN/screenshot.sh")" "1"

# --- battery ---------------------------------------------------------------

# The dimming is logged rather than swallowed. It used to be `exit 0`, which is
# why nothing noticed that it ran on every tick instead of once per crossing.
BLOG="$TMP/brightness"
cat >"$STUB/brightnessctl" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"${BRIGHT_LOG:?}"
STUBEOF
chmod +x "$STUB/brightnessctl"
NLOG="$TMP/notifications"
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"${NOTIFY_LOG:?}"
STUBEOF
chmod +x "$STUB/notify-send"

battery_at() {
  cat >"$STUB/upower" <<STUBEOF
#!/bin/bash
[[ \$1 == -e ]] && { echo /org/freedesktop/UPower/devices/BAT0; exit 0; }
echo "    percentage:          $1%"
echo "    state:               discharging"
STUBEOF
  chmod +x "$STUB/upower"
}

FLAG=/tmp/battery-notification-flag
run_battery() {
  battery_at "$1"
  NOTIFY_LOG="$NLOG" BRIGHT_LOG="$BLOG" PATH="$STUB:$PATH" \
    bash "$BIN/battery-monitor.sh" >/dev/null 2>&1
}

# 9% is at or below 20, 15 and 10. The old loop notified once for each.
rm -f "$FLAG"; : >"$NLOG"; : >"$BLOG"
run_battery 9
check "one reading crossing three thresholds notifies once" \
  "$(grep -c 'Battery Low' "$NLOG")" "1"
check "the notification names the level the battery is at" \
  "$(grep -c 'Battery at 9%' "$NLOG")" "1"

# 2% is at or below all five.
rm -f "$FLAG"; : >"$NLOG"; : >"$BLOG"
run_battery 2
check "one reading crossing five thresholds still notifies once" \
  "$(grep -c 'Battery Low' "$NLOG")" "1"

# Falling into a lower band must notify again. This is the half that a naive
# once-ever flag would break, so it is asserted rather than assumed.
rm -f "$FLAG"; : >"$NLOG"; : >"$BLOG"
run_battery 9
run_battery 4
check "falling into a lower band notifies again" \
  "$(grep -c 'Battery Low' "$NLOG")" "2"

# Staying in the same band must not.
: >"$NLOG"; : >"$BLOG"
run_battery 4
check "a second reading in the same band does not notify again" \
  "$(grep -c 'Battery Low' "$NLOG")" "0"

# The dimming has to follow the same rule as the message, and did not. The
# timer fires every 30 seconds, so a battery sitting below 20% had its screen
# forced back to 5% twice a minute: raise it to read something and half a
# minute later it was dark again. Four ticks in one band produced four sets.
rm -f "$FLAG"; : >"$NLOG"; : >"$BLOG"
run_battery 9
run_battery 9
run_battery 9
run_battery 9
check "four readings in one band dim the screen once, not four times" \
  "$(grep -c 'set 5%' "$BLOG")" "1"
check "and notify once" "$(grep -c 'Battery Low' "$NLOG")" "1"

# Falling further still has to act, or the fix above would be a way to dim
# never rather than once.
run_battery 4
check "falling into a lower band dims again" \
  "$(grep -c 'set 5%' "$BLOG")" "2"

# Charging clears the flag, so the next discharge dims again.
cat >"$STUB/upower" <<'STUBEOF'
#!/bin/bash
[[ $1 == -e ]] && { echo /org/freedesktop/UPower/devices/BAT0; exit 0; }
echo "    percentage:          80%"
echo "    state:               charging"
STUBEOF
chmod +x "$STUB/upower"
NOTIFY_LOG="$NLOG" BRIGHT_LOG="$BLOG" PATH="$STUB:$PATH" \
  bash "$BIN/battery-monitor.sh" >/dev/null 2>&1
check "charging clears the flag" \
  "$([[ -f $FLAG ]] && echo present || echo gone)" "gone"
: >"$BLOG"
run_battery 9
check "and the next discharge dims once more" \
  "$(grep -c 'set 5%' "$BLOG")" "1"

# Above every threshold nothing happens at all.
rm -f "$FLAG"; : >"$NLOG"; : >"$BLOG"
run_battery 55
check "a healthy battery is left alone" "$(wc -l <"$BLOG" | tr -d ' ')" "0"
check "and says nothing" "$(wc -l <"$NLOG" | tr -d ' ')" "0"

rm -f "$FLAG"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
