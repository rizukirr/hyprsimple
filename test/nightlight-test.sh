#!/bin/bash
# Checks toggle-nightlight.sh against a stubbed hyprsunset.
#
# The key meant to warm the screen could not warm it when hyprsunset was not
# answering, and said it had. hyprctl prints its connection error on stdout,
# so the old `grep -oE '[0-9]+'` read the digits out of the socket path, the
# comparison against 6000 failed, and the script asked for 6000: the daylight
# end, on a press meant to do the opposite. It then reported success about a
# command that had also failed.
#
# Nothing here talks to a real hyprsunset or changes a real screen.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/.local/bin/toggle-nightlight.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}
for helper in pass fail check; do
  declare -F "$helper" >/dev/null || { printf 'not ok - helper %s missing\n' "$helper" >&2; exit 1; }
done

STUB="$TMP/bin"; mkdir -p "$STUB"
HLOG="$TMP/hyprctl-calls"
NLOG="$TMP/notifications"
STATE="$TMP/temperature"

cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUBEOF

# A live hyprsunset: a query answers with the number alone, a set answers "ok".
# Both formats were read off the real thing rather than assumed.
cat >"$STUB/hyprctl-live" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
if [[ $1 == hyprsunset && $2 == temperature && -z ${3-} ]]; then cat "$TEMP_STATE"; echo; exit 0; fi
if [[ $1 == hyprsunset && $2 == temperature && -n ${3-} ]]; then printf '%s' "$3" >"$TEMP_STATE"; echo ok; exit 0; fi
exit 1
STUBEOF

# A dead one, printing the real message hyprctl gives, on stdout, which is what
# defeated the redirection to /dev/null and fed the digit scrape.
cat >"$STUB/hyprctl-dead" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
echo "Couldn't connect to /run/user/1000/hypr/efb50993780079460b0cbed1363e2166a2de1d9f_1788756256_4119465/.hyprsunset.sock. (3)"
exit 1
STUBEOF

printf '#!/bin/bash\nexit 0\n' >"$STUB/uwsm"
printf '#!/bin/bash\nexit 0\n' >"$STUB/pgrep"
chmod +x "$STUB"/*

use_hyprctl() { cp "$STUB/hyprctl-$1" "$STUB/hyprctl"; chmod +x "$STUB/hyprctl"; }
press() {
  HYPRCTL_LOG="$HLOG" NOTIFY_LOG="$NLOG" TEMP_STATE="$STATE" \
    HYPRSIMPLE_SUNSET_WAIT=2 PATH="$STUB:/usr/bin:/bin" \
    bash "$SCRIPT" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

# ---- the premise: that error really does scrape as digits ------------------
#
# Asserted rather than described. If hyprctl's message ever stops carrying
# digits, the checks below would pass for a reason that has nothing to do with
# the fix.
scraped=$(PATH="$STUB:/usr/bin:/bin" HYPRCTL_LOG=/dev/null "$STUB/hyprctl-dead" hyprsunset temperature |
  grep -oE '[0-9]+' | tr '\n' ' ')
check "the connection error scrapes into digits, which is what the old parse read" \
  "$([[ -n ${scraped// /} ]] && echo yes || echo no)" "yes"
check "and none of them is the daylight temperature, so the comparison could not match" \
  "$(printf '%s' "$scraped" | tr ' ' '\n' | grep -cx 6000)" "0"

# ---- a live hyprsunset toggles both ways -----------------------------------

use_hyprctl live
printf '6000' >"$STATE"; : >"$NLOG"; : >"$HLOG"

press
check "from daylight, one press warms the screen" "$(cat "$STATE")" "4000"
check "and says so" "$(grep -c 'Warm screen temperature (4000K)' "$NLOG")" "1"
check "and exits 0" "$(cat "$TMP/rc")" "0"

press
check "a second press returns it to daylight" "$(cat "$STATE")" "6000"
check "and says that" "$(grep -c 'Daylight screen temperature (6000K)' "$NLOG")" "1"

press
check "and a third warms it again, so the toggle really alternates" "$(cat "$STATE")" "4000"

# A temperature that is neither end, as a hyprsunset.conf profile can leave it.
printf '4500' >"$STATE"; : >"$NLOG"
press
check "from a profile temperature, a press goes to daylight" "$(cat "$STATE")" "6000"

# ---- a dead hyprsunset is reported, not papered over -----------------------

use_hyprctl dead
: >"$NLOG"; : >"$HLOG"
press

check "with hyprsunset not answering, nothing is claimed about the temperature" \
  "$(grep -c 'screen temperature (' "$NLOG")" "0"
check "the user is told hyprsunset is not responding" \
  "$(grep -c 'not responding' "$NLOG")" "1"
check "and the message is critical, so it is not lost among the ordinary ones" \
  "$(grep -c -- '-u critical' "$NLOG")" "1"
check "and the script exits non-zero" \
  "$([[ $(cat "$TMP/rc") != "0" ]] && echo nonzero || echo zero)" "nonzero"

# The heart of it: no temperature is asked for at all. The old script asked for
# 6000 here, which is the wrong direction as well as a failed call.
check "no temperature is set when the state could not be read" \
  "$(grep -c 'hyprsunset temperature 6000' "$HLOG")" "0"
check "and none at the other end either" \
  "$(grep -c 'hyprsunset temperature 4000' "$HLOG")" "0"

# ---- a set that is refused is reported too ---------------------------------
#
# Reading answers, setting fails. The old script sent its notification without
# looking at the answer at all.
cat >"$STUB/hyprctl" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$HYPRCTL_LOG"
if [[ $1 == hyprsunset && $2 == temperature && -z ${3-} ]]; then echo 6000; exit 0; fi
echo "error"
exit 1
STUBEOF
chmod +x "$STUB/hyprctl"
: >"$NLOG"; : >"$HLOG"
press
check "a refused set is not reported as a temperature change" \
  "$(grep -c 'screen temperature (' "$NLOG")" "0"
check "the user is told it would not be set" \
  "$(grep -c 'would not set' "$NLOG")" "1"
check "and the script exits non-zero" \
  "$([[ $(cat "$TMP/rc") != "0" ]] && echo nonzero || echo zero)" "nonzero"

# ---- the shape of the parse ------------------------------------------------
#
# Comments stripped, because the script explains the old scrape in one.
code() { sed 's/#.*//' "$SCRIPT"; }
check "the unanchored digit scrape is gone" \
  "$(code "$SCRIPT" | grep -c "grep -oE '\[0-9\]+'")" "0"
check "and the reading is anchored to a bare number" \
  "$(code "$SCRIPT" | grep -c '\^\[0-9\]+\$')" "1"
check "and the fixed sleep after starting hyprsunset is gone" \
  "$(code "$SCRIPT" | grep -c '^ *sleep 1$')" "0"
check "while the wait that replaced it is bounded" \
  "$(code "$SCRIPT" | grep -c 'HYPRSIMPLE_SUNSET_WAIT')" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
