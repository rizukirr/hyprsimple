#!/bin/bash
# wifi.sh had no test at all, and the reason was structural: it read
# /sys/class/net directly, so neither answer could be arranged on a machine
# whose own wireless hardware is fixed. Its sibling wifi-powersave.sh was given
# an overridable root for exactly that reason and has six checks. This one had
# none, and two bugs.
#
# It found the interface by looking for the `wireless` directory, which is the
# WEXT compatibility layer and a kernel option (CONFIG_CFG80211_WEXT). cfg80211
# creates phy80211 for every wireless netdev unconditionally, so a machine
# built without WEXT has working WiFi and no `wireless` directory.
#
# And the interface was required before the backend was chosen, though only the
# iwd branch uses it. NetworkManager finds its own device. Measured before the
# fix, inside a namespace with /sys/class/net masked: "No WiFi interface found",
# exit 1, and nmcli never called once.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WIFI="$REPO/.local/bin/wifi.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"
LOG="$TMP/calls.log"
mkdir -p "$STUB"

cat >"$STUB/nmcli" <<'STUBEOF'
#!/bin/bash
printf 'nmcli %s\n' "$*" >>"$CALL_LOG"
exit "${NMCLI_RC:-0}"
STUBEOF
cat >"$STUB/iwctl" <<'STUBEOF'
#!/bin/bash
printf 'iwctl %s\n' "$*" >>"$CALL_LOG"
STUBEOF
# is-active answers for whichever service the test says is running.
cat >"$STUB/systemctl" <<'STUBEOF'
#!/bin/bash
for arg in "$@"; do
  [[ $arg == "${RUNNING_SERVICE:-}" ]] && exit 0
done
exit 3
STUBEOF
chmod +x "$STUB"/*

# Three sysfs shapes: a modern interface with both markers, one with only
# phy80211 as a WEXT-less kernel gives, and nothing at all.
mk_sysfs() {
  local root="$TMP/sysfs-$1"
  rm -rf "$root"
  mkdir -p "$root"
  case "$1" in
    both) mkdir -p "$root/wlan0/wireless"; : >"$root/wlan0/phy80211" ;;
    phy-only) mkdir -p "$root/wlan0"; : >"$root/wlan0/phy80211" ;;
    none) mkdir -p "$root/enp4s0" ;;
  esac
  printf '%s' "$root"
}

run() {
  local sysfs="$1" service="$2"
  shift 2
  : >"$LOG"
  CALL_LOG="$LOG" NMCLI_RC="${NMCLI_RC:-0}" RUNNING_SERVICE="$service" \
    HYPRSIMPLE_SYSFS_NET="$sysfs" PATH="$STUB:/usr/bin:/bin" \
    bash "$WIFI" "$@" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
calls() { cat "$LOG" 2>/dev/null; }

# ---- the override works at all -------------------------------------------
#
# Asserted before anything is read from it. If the script ignored
# HYPRSIMPLE_SYSFS_NET it would read the real machine's sysfs, every case below
# would see whatever hardware the runner happens to have, and this suite would
# be testing that instead.

check "wifi.sh honours HYPRSIMPLE_SYSFS_NET" \
  "$(grep -c 'HYPRSIMPLE_SYSFS_NET' "$WIFI")" "1"

# ---- NetworkManager does not need the interface to be visible -------------

run "$(mk_sysfs none)" NetworkManager MyNet
check "nmcli connects even with no interface visible in sysfs" \
  "$(calls | grep -c 'nmcli device wifi connect MyNet')" "1"
check "and does not refuse before asking nmcli" "$(rc)" "0"

run "$(mk_sysfs both)" NetworkManager
check "no argument lists networks" \
  "$(calls | grep -c 'device wifi list')" "1"
check "and rescans first" \
  "$(calls | grep -c 'device wifi rescan')" "1"

run "$(mk_sysfs both)" NetworkManager MyNet hunter2
check "a passphrase is passed through" \
  "$(calls | grep -c 'connect MyNet password hunter2')" "1"

NMCLI_RC=4 run "$(mk_sysfs both)" NetworkManager MyNet
check "a failed connect is not reported as success" "$(rc)" "4"
unset NMCLI_RC

# ---- iwd is the branch that genuinely needs the interface -----------------

run "$(mk_sysfs both)" iwd MyNet
check "iwd connects using the detected interface" \
  "$(calls | grep -c 'iwctl station wlan0 connect MyNet')" "1"

run "$(mk_sysfs none)" iwd MyNet
check "iwd with no interface says so" \
  "$(grep -c 'No WiFi interface found' "$TMP/out")" "1"
check "and exits non-zero" "$(rc)" "1"
check "and runs no iwctl" "$(calls | grep -c iwctl)" "0"

# ---- a kernel with no WEXT compatibility layer ---------------------------
#
# The case the old detection missed entirely: phy80211 present, no `wireless`.

run "$(mk_sysfs phy-only)" iwd MyNet
check "an interface with only phy80211 is still found" \
  "$(calls | grep -c 'iwctl station wlan0 connect MyNet')" "1"

# ---- neither backend installed -------------------------------------------

# A PATH holding only what the script needs and neither backend. Keeping
# /usr/bin on it would have found this machine's real nmcli, which is exactly
# what happened the first time this check was written: it failed because the
# case it claimed to set up had not been set up.
NOBACKEND="$TMP/nobackend"
mkdir -p "$NOBACKEND"
# bash included: with PATH replaced, the shell resolves the interpreter with
# the new PATH too, so leaving it out made every run exit 127 with no output
# and the check failed against a script that had never started.
for c in bash basename dirname; do ln -sf "$(command -v "$c")" "$NOBACKEND/$c"; done
cp "$STUB/systemctl" "$NOBACKEND/systemctl"

check "the no-backend fixture really has no backend" \
  "$(PATH="$NOBACKEND" command -v nmcli iwctl 2>/dev/null | grep -c .)" "0"

: >"$TMP/none.log"
CALL_LOG="$TMP/none.log" RUNNING_SERVICE=none \
  HYPRSIMPLE_SYSFS_NET="$(mk_sysfs both)" PATH="$NOBACKEND" \
  bash "$WIFI" MyNet >"$TMP/out" 2>&1
check "with no backend installed it says which ones it needs" \
  "$(grep -c 'need NetworkManager/nmcli or iwd/iwctl' "$TMP/out")" "1"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
