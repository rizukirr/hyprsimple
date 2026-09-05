#!/bin/bash
# bluetooth-toggle.sh read the adapter's power state from dbus at a hardcoded
# object path:
#
#   dbus-send --system ... --dest=org.bluez /org/bluez/hci0 ... Powered
#
# and wrote it with `bluetoothctl power on|off`, which acts on the default
# controller. The two disagree on any machine whose adapter is not hci0, which
# is what a USB dongle gets whenever a built-in radio already holds hci0.
#
# When they disagree the read fails, is_powered is permanently false, and the
# toggle powers the adapter on every single time and never off. That is the
# same one-way switch monitor-mirror-toggle.sh had, where a check that could
# never be true made a toggle act in one direction only.
#
# Reading now goes through bluetoothctl too, so both halves mean the same
# adapter whatever it is called.
#
# Nothing here touches the real adapter: bluetoothctl is a stub.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/.local/bin/bluetooth-toggle.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"

# Answers `show` from the state the test sets, and records the writes. The
# controller's name is a variable, because being called hci1 is the whole point.
cat >"$STUB/bluetoothctl" <<'STUBEOF'
#!/bin/bash
printf 'bluetoothctl %s\n' "$*" >>"$CALL_LOG"
if [[ $1 == show ]]; then
  [[ ${ADAPTER:-none} == none ]] && { echo "No default controller available"; exit 1; }
  printf 'Controller E8:BF:B8:DC:49:42 (public)\n'
  printf '\tName: test\n'
  printf '\tPowered: %s\n' "${POWERED:-no}"
fi
exit 0
STUBEOF
# Present so the old code path would have something to call, and so its absence
# is never what makes a check pass.
cat >"$STUB/dbus-send" <<'STUBEOF'
#!/bin/bash
printf 'dbus-send %s\n' "$*" >>"$CALL_LOG"
exit 1
STUBEOF
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf 'notify-send %s\n' "$*" >>"$CALL_LOG"
STUBEOF
chmod +x "$STUB"/*

run() {
  : >"$LOG"
  CALL_LOG="$LOG" ADAPTER="${1:-hci0}" POWERED="${2:-no}" \
    PATH="$STUB:/usr/bin:/bin" bash "$SCRIPT" "${3:-toggle}" >"$TMP/out" 2>"$TMP/err"
  printf '%s' "$?" >"$TMP/rc"
}

# --- the adapter's name must not matter -------------------------------------

for adapter in hci0 hci1 hci7; do
  run "$adapter" yes toggle
  check "a powered adapter called $adapter is turned off" \
    "$(grep -c 'bluetoothctl power off' "$LOG")" "1"
  run "$adapter" no toggle
  check "an unpowered adapter called $adapter is turned on" \
    "$(grep -c 'bluetoothctl power on' "$LOG")" "1"
done

# The old path is gone: nothing asks dbus about a hardcoded object any more.
run hci1 yes toggle
check "no dbus call names a hardcoded adapter" "$(grep -c 'org/bluez/hci' "$LOG")" "0"
# Comments are stripped first. The comment left in the script explains the old
# path by name, and grepping the raw file counted that. suite-hygiene-test.sh
# uses the same helper for the same reason.
code_of() { sed 's/#.*//' "$1"; }
check "and the script's code no longer contains that path" \
  "$(code_of "$SCRIPT" | grep -c '/org/bluez/hci0')" "0"
# The stripper has to leave real code behind, or the check above passes on an
# empty file.
check "stripping comments leaves the script's code intact" \
  "$(code_of "$SCRIPT" | grep -c 'bluetoothctl power off')" "1"

# --- status ------------------------------------------------------------------

run hci1 yes status
check "status reports true for a powered adapter on any name" "$(cat "$TMP/out")" "true"
run hci1 no status
check "and false for an unpowered one" "$(cat "$TMP/out")" "false"

# --- no adapter at all -------------------------------------------------------

run none no toggle
check "with no adapter the toggle exits non-zero" "$(cat "$TMP/rc")" "1"
check "and says so" "$(grep -c 'No Bluetooth adapter found' "$LOG")" "1"
check "and powers nothing" "$(grep -c 'bluetoothctl power' "$LOG")" "0"

# --- usage -------------------------------------------------------------------
#
# status is read from stdout by anything scripting this, so the usage line must
# not arrive on the same channel as true or false.
run hci0 yes bogus
check "an unknown argument exits non-zero" "$(cat "$TMP/rc")" "1"
check "and writes nothing to stdout" "$(wc -c <"$TMP/out" | tr -d ' ')" "0"
check "and puts the usage line on stderr" "$(grep -c 'Usage: bluetooth-toggle.sh' "$TMP/err")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
