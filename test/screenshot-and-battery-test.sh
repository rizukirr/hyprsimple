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

# hyprshot notifies unless told not to, so a mode that also notifies here sent
# two messages for one keypress. Measured before the fix, with a hyprshot stub
# notifying the way the real one does: two notifications, "Image copied to the
# clipboard" and "Copied to clipboard".
cat >"$STUB/hyprshot" <<'STUBEOF'
#!/bin/bash
printf '%s|%s
' "$#" "$*" >>"${CALL_LOG:?}"
# The real hyprshot notifies unless --silent is passed.
for a in "$@"; do [[ $a == --silent ]] && exit 0; done
notify-send "Screenshot saved" "Image copied to the clipboard"
STUBEOF
chmod +x "$STUB/hyprshot"
NLOG_SHOT="$TMP/shot-notifications"
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s
' "$*" >>"${NOTIFY_LOG:?}"
STUBEOF
chmod +x "$STUB/notify-send"

for mode in clipboard window region monitor; do
  : >"$LOG"; : >"$NLOG_SHOT"
  CALL_LOG="$LOG" NOTIFY_LOG="$NLOG_SHOT" HOME="$SPACED" PATH="$STUB:$PATH"     bash "$BIN/screenshot.sh" "$mode" >/dev/null 2>&1
  check "screenshot $mode notifies exactly once" \
    "$(wc -l <"$NLOG_SHOT" | tr -d ' ')" "1"
done

# A mode that is not one of the four used to fall past every branch and exit 0.
: >"$LOG"; : >"$NLOG_SHOT"
CALL_LOG="$LOG" NOTIFY_LOG="$NLOG_SHOT" HOME="$SPACED" PATH="$STUB:$PATH" \
  bash "$BIN/screenshot.sh" clipbaord >"$TMP/shot-out" 2>"$TMP/shot-err"
check "an unknown mode exits non-zero" "$?" "1"
check "and takes no screenshot" "$(wc -l <"$LOG" | tr -d ' ')" "0"
check "and puts its usage on stderr" "$(grep -c 'Usage:' "$TMP/shot-err")" "1"
check "and nothing on stdout" "$(wc -c <"$TMP/shot-out" | tr -d ' ')" "0"

# The original hyprshot stub, restored for anything after this point.
cat >"$STUB/hyprshot" <<'STUBEOF'
#!/bin/bash
printf '%s|%s
' "$#" "$*" >>"${CALL_LOG:?}"
STUBEOF
chmod +x "$STUB/hyprshot"
printf '#!/bin/bash
exit 0
' >"$STUB/notify-send"; chmod +x "$STUB/notify-send"
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

# --- the monitor waits for a session to notify -------------------------------
#
# battery-monitor.timer was WantedBy=timers.target, so it started with the user
# manager, before any compositor. The service said
# After=graphical-session.target, which is ordering only and does nothing when
# that target is not part of the same job.
#
# Measured on a login: "Starting Battery Monitor Service..." at 11:54:23 and
# "uwsm: Selected compositor ID" in the same second, after it. With a low
# battery that means this script dims the panel to 5% at the greeter, and its
# notify-send activates dunst over D-Bus into a session with no Wayland
# display, where dunst aborts on "Couldn't initialize X11 output", is retried
# five times and burns its start limit. The notification is lost and
# dunst.service is left failed, which #106 made visible.

UNITS="$REPO/.config/systemd/user"
TIMER="$UNITS/battery-monitor.timer"
SERVICE="$UNITS/battery-monitor.service"

# Comments stripped before counting. The new timer explains in a comment what
# it used to say, and an unanchored grep counts that explanation as the
# setting, which is how this check first passed the wrong way round.
unit_code() { sed 's/^[[:space:]]*#.*//' "$1"; }

check "the timer is wanted by the graphical session" \
  "$(unit_code "$TIMER" | grep -c '^WantedBy=graphical-session.target$')" "1"
check "and not by timers.target, which starts with the user manager" \
  "$(unit_code "$TIMER" | grep -c 'WantedBy=timers.target')" "0"
check "stripping comments leaves the settings intact" \
  "$(unit_code "$TIMER" | grep -c '^Requires=')" "1"
check "and is part of the session, so it stops with it" \
  "$(grep -c '^PartOf=graphical-session.target$' "$TIMER")" "1"
check "the schedule counts from the session, not from boot" \
  "$(grep -c '^OnActiveSec=' "$TIMER")" "1"
check "so OnBootSec is gone" "$(unit_code "$TIMER" | grep -c '^OnBootSec=')" "0"
check "and Persistent with it, there being no missed run worth catching up" \
  "$(unit_code "$TIMER" | grep -c '^Persistent=')" "0"
check "the service is part of the session too" \
  "$(grep -c '^PartOf=graphical-session.target$' "$SERVICE")" "1"
check "and has no Install section inviting it to be enabled on its own" \
  "$(unit_code "$SERVICE" | grep -c '^\[Install\]')" "0"
check "the timer still requires the service, or nothing would run" \
  "$(grep -c '^Requires=battery-monitor.service$' "$TIMER")" "1"

# systemd's own verdict, where it is available.
if ! command -v systemd-analyze >/dev/null 2>&1; then
  pass "systemd-analyze is not installed here, so its verdict is skipped"
else
  complaints=$(systemd-analyze --user verify "$TIMER" 2>&1 | grep -c . || true)
  check "systemd accepts the timer with no complaint" "$complaints" "0"
fi

# install.sh must not start it during an install, where no session exists.
check "install.sh enables the timer without starting it" \
  "$(grep -c 'systemctl --user enable battery-monitor.timer$' "$REPO/install.sh")" "1"
check "and no longer uses --now, which fired it with no compositor" \
  "$(grep -c 'enable --now battery-monitor.timer' "$REPO/install.sh")" "0"

# --- and the change reaches machines that already exist ----------------------

MIGRATION="$REPO/migrations/1788702842.sh"
check "a migration carries it" "$([[ -f $MIGRATION ]] && echo yes || echo no)" "yes"

PRE="$REPO/test/fixtures/pre-session-timer"
check "it records two checksums, one per unit" \
  "$(grep -cE '^(TIMER|SERVICE)_SUM="[a-f0-9]{32}"$' "$MIGRATION")" "2"
check "and the timer fixture is the version it records" \
  "$(md5sum "$PRE/battery-monitor.timer" | cut -d' ' -f1)" \
  "$(grep -oE '^TIMER_SUM="[a-f0-9]+"' "$MIGRATION" | cut -d'"' -f2)"
check "and the service fixture likewise" \
  "$(md5sum "$PRE/battery-monitor.service" | cut -d' ' -f1)" \
  "$(grep -oE '^SERVICE_SUM="[a-f0-9]+"' "$MIGRATION" | cut -d'"' -f2)"
check "and the fixture really is the old shape, or this proves nothing" \
  "$(grep -c 'WantedBy=timers.target' "$PRE/battery-monitor.timer")" "1"

BHOME="$TMP/battery-home"
BSTUB="$TMP/battery-bin"; mkdir -p "$BSTUB"
cat >"$BSTUB/systemctl" <<'STUBEOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$SYSTEMCTL_LOG"
case "$*" in
  *"is-enabled battery-monitor.timer") exit "${TIMER_ENABLED_RC:-0}" ;;
  *"is-active graphical-session.target") exit "${SESSION_RC:-0}" ;;
esac
exit 0
STUBEOF
chmod +x "$BSTUB/systemctl"

setup_units() {
  rm -rf "${TMP:?}/battery-home"; mkdir -p "$BHOME/.config/systemd/user"
  cp "$PRE/battery-monitor.timer" "$PRE/battery-monitor.service" \
    "$BHOME/.config/systemd/user/"
}
run_migration() {
  : >"$TMP/systemctl.log"
  SYSTEMCTL_LOG="$TMP/systemctl.log" HOME="$BHOME" HYPRSIMPLE_PATH="$REPO" \
    PATH="$BSTUB:/usr/bin:/bin" "$@" bash "$MIGRATION" >"$TMP/mig-out" 2>&1
}

setup_units
run_migration
check "an unedited timer is replaced" \
  "$(grep -c 'WantedBy=graphical-session.target' "$BHOME/.config/systemd/user/battery-monitor.timer")" "1"
check "and the service with it" \
  "$(grep -c 'PartOf=graphical-session.target' "$BHOME/.config/systemd/user/battery-monitor.service")" "1"
check "the enabling symlink is moved, not left under timers.target" \
  "$(grep -c 'disable battery-monitor.timer' "$TMP/systemctl.log")" "1"
check "and re-enabled afterwards" \
  "$(grep -c 'enable battery-monitor.timer' "$TMP/systemctl.log")" "1"
check "with a daemon-reload, or systemd would still hold the old unit" \
  "$(grep -c 'daemon-reload' "$TMP/systemctl.log")" "1"

# A machine that turned the timer off keeps it off.
setup_units
run_migration env TIMER_ENABLED_RC=1
check "a disabled timer is not enabled behind the user's back" \
  "$(grep -c 'enable battery-monitor.timer' "$TMP/systemctl.log")" "0"
check "but the units are still corrected" \
  "$(grep -c 'WantedBy=graphical-session.target' "$BHOME/.config/systemd/user/battery-monitor.timer")" "1"

# An edited unit is left alone and named.
setup_units
printf '[Unit]\nDescription=mine\n' >"$BHOME/.config/systemd/user/battery-monitor.timer"
run_migration
check "an edited unit is left as it is" \
  "$(grep -c 'Description=mine' "$BHOME/.config/systemd/user/battery-monitor.timer")" "1"
check "and named, so the user knows theirs still runs early" \
  "$(grep -c 'battery-monitor.timer' "$TMP/mig-out")" "1"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
