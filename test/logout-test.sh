#!/bin/bash
# hypr-logout.sh said one thing and did another.
#
#   # Closes all windows first so apps like Chrome shut down cleanly,
#   # then stops the UWSM session.
#
#   nohup bash -c "sleep 2 && uwsm stop" >/dev/null 2>&1 &
#   ... send closewindow to every client ...
#   sleep 1
#
# The stop was scheduled before a single close was sent, so the session was
# torn down two seconds after the script started whatever else had happened.
# hyprctl dispatch closewindow returns as soon as the request is sent, and an
# application decides for itself how long it needs afterwards, so two seconds
# was a guess about every program at once. A browser still flushing its profile
# when the timer fired was killed, which is the one thing the script exists to
# prevent.
#
# It is reached from SUPER+X and from the power menu's Logout, so both go
# through this.
#
# Every hyprctl and uwsm call here is a stub. Nothing closes a real window and
# nothing stops a real session.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/.local/bin/hypr-logout.sh"
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

# Models a compositor whose windows take a while to go. CLOSES_NEEDED is how
# many polls must pass after the closes are sent before the list empties, which
# is the application's own shutdown time.
cat >"$STUB/hyprctl" <<'STUBEOF'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
  "clients -j")
    if [[ ! -f $STATE/closed ]]; then
      printf '[{"address":"0x1"},{"address":"0x2"}]\n'
      exit 0
    fi
    polls=$(cat "$STATE/polls" 2>/dev/null || echo 0)
    polls=$((polls + 1)); printf '%s' "$polls" >"$STATE/polls"
    if (( polls > ${CLOSES_NEEDED:-1} )); then printf '[]\n'; else printf '[{"address":"0x1"}]\n'; fi
    ;;
  "dispatch closewindow"*) : >"$STATE/closed" ;;
esac
STUBEOF
cat >"$STUB/uwsm" <<'STUBEOF'
#!/bin/bash
printf 'uwsm %s at %s\n' "$*" "$(date +%s%3N)" >>"$CALL_LOG"
STUBEOF
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf 'notify-send %s\n' "$*" >>"$CALL_LOG"
STUBEOF
chmod +x "$STUB"/*

run_logout() {
  rm -rf "${TMP:?}/state"; mkdir -p "$TMP/state"
  : >"$LOG"
  local start end
  start=$(date +%s%3N)
  CALL_LOG="$LOG" STATE="$TMP/state" CLOSES_NEEDED="${1:-1}" \
    HYPRSIMPLE_LOGOUT_TIMEOUT_MS="${2:-8000}" \
    PATH="$STUB:/usr/bin:/bin" bash "$SCRIPT" >/dev/null 2>&1
  end=$(date +%s%3N)
  printf '%s' "$((end - start))" >"$TMP/elapsed"
}

# --- the order the comment always promised ----------------------------------

run_logout 1
close_line=$(grep -n 'dispatch closewindow' "$LOG" | head -1 | cut -d: -f1)
stop_line=$(grep -n '^uwsm stop' "$LOG" | head -1 | cut -d: -f1)
check "every window is closed" "$(grep -c 'dispatch closewindow' "$LOG")" "2"
check "and the session is stopped" "$(grep -c '^uwsm stop' "$LOG")" "1"
if [[ -n $close_line && -n $stop_line ]] && (( close_line < stop_line )); then
  pass "and the stop comes after the closes, not before them"
else
  fail "the stop was issued at line ${stop_line:-none}, the first close at ${close_line:-none}"
fi

# --- it waits for slow applications -----------------------------------------
#
# The old code stopped the session 2000ms in regardless. An application taking
# longer than that to exit was killed mid-shutdown.
run_logout 25 8000
elapsed=$(cat "$TMP/elapsed")
if (( elapsed > 2000 )); then
  pass "a window taking longer than the old 2s timer is waited for (${elapsed}ms)"
else
  fail "returned in ${elapsed}ms, so a slow window is still not being waited for"
fi
check "and the session is still stopped once it goes" "$(grep -c '^uwsm stop' "$LOG")" "1"
check "and nothing is reported, because it did close" \
  "$(grep -c 'did not close' "$LOG")" "0"

# --- it does not wait forever ------------------------------------------------

run_logout 100000 600
elapsed=$(cat "$TMP/elapsed")
if (( elapsed < 3000 )); then
  pass "a window that never closes does not keep the session alive (${elapsed}ms)"
else
  fail "waited ${elapsed}ms on a window that never closes"
fi
check "the session is stopped anyway" "$(grep -c '^uwsm stop' "$LOG")" "1"
check "and the user is told why" "$(grep -c 'did not close in time' "$LOG")" "1"

# --- the old shape is gone ---------------------------------------------------

code_of() { sed 's/#.*//' "$1"; }
check "no background timer schedules the stop any more" \
  "$(code_of "$SCRIPT" | grep -c 'nohup')" "0"
check "and the stop is not behind a fixed sleep" \
  "$(code_of "$SCRIPT" | grep -cE 'sleep 2 && uwsm stop')" "0"
check "stripping comments leaves the code intact" \
  "$(code_of "$SCRIPT" | grep -c 'uwsm stop')" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
