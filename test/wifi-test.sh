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

# Stdin is closed, so every run below takes the no-terminal branch unless
# run_on_tty is used. Left inherited, the answer would depend on whether the
# suite was started from a shell or by CI, and the two branches differ.
run() {
  local sysfs="$1" service="$2"
  shift 2
  : >"$LOG"
  CALL_LOG="$LOG" NMCLI_RC="${NMCLI_RC:-0}" RUNNING_SERVICE="$service" \
    HYPRSIMPLE_SYSFS_NET="$sysfs" PATH="$STUB:/usr/bin:/bin" \
    bash "$WIFI" "$@" >"$TMP/out" 2>&1 </dev/null
  printf '%s' "$?" >"$TMP/rc"
}

# The same, with a real terminal on stdin. script(1) is the only way to give
# one: a redirect from a file or a pipe leaves [[ -t 0 ]] false, which is the
# branch this exists to tell apart.
SCRIPT_BIN="$(command -v script || true)"

run_on_tty() {
  local sysfs="$1" service="$2"
  shift 2
  : >"$LOG"
  # The arguments go through a generated wrapper rather than into script's -c
  # string. That string is a shell command line, so an SSID with a space in it
  # would need requoting there, and an SSID with a space is the reported case.
  {
    printf '#!/bin/bash\n'
    printf 'exec bash %q' "$WIFI"
    printf ' %q' "$@"
    printf '\n'
  } >"$TMP/tty-run.sh"
  chmod +x "$TMP/tty-run.sh"
  CALL_LOG="$LOG" NMCLI_RC="${NMCLI_RC:-0}" RUNNING_SERVICE="$service" \
    HYPRSIMPLE_SYSFS_NET="$sysfs" PATH="$STUB:/usr/bin:/bin" \
    "$SCRIPT_BIN" -qec "$TMP/tty-run.sh" /dev/null >"$TMP/out" 2>&1 </dev/null
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

# ---- --help -----------------------------------------------------------------
#
# The usage lived only in a comment at the top of the script, so the way to
# find out what the second argument was for was to read the source. It also has
# to answer before the backend is chosen: the interface detection and the
# backend choice both come before any argument is looked at, so on a machine
# with neither nmcli nor iwctl, asking for help got "No supported WiFi backend
# found" and exit 1.

for flag in --help -h; do
  run "$(mk_sysfs both)" NetworkManager "$flag"
  check "$flag prints the usage" "$(grep -c '^Usage: wifi.sh' "$TMP/out")" "1"
  check "and exits 0" "$(rc)" "0"
  check "and touches no backend" "$(calls | wc -l | tr -d ' ')" "0"
done

check "the usage explains what the second argument is for" \
  "$(grep -c 'SSID PASSWORD' "$TMP/out")" "1"
check "and that a secured network asks when it can" \
  "$(grep -c 'asks for the password' "$TMP/out")" "1"
check "and how to quote an SSID with a space in it" \
  "$(grep -c 'Quote an SSID' "$TMP/out")" "1"

# With no wireless hardware, no backend installed and nothing running, which is
# the case that used to answer with an error.
# The real tools the script itself needs, and nothing else. Linking them in by
# name rather than adding /usr/bin, which would bring the maintainer's own
# nmcli back and make "no backend installed" untrue.
NO_BACKEND="$TMP/empty-bin"
mkdir -p "$NO_BACKEND"
for tool in cat basename; do
  ln -sf "$(command -v "$tool")" "$NO_BACKEND/$tool"
done
BASH_BIN="$(command -v bash)"

HYPRSIMPLE_SYSFS_NET="$(mk_sysfs none)" PATH="$NO_BACKEND" \
  "$BASH_BIN" "$WIFI" --help >"$TMP/out" 2>&1 </dev/null
check "--help works with no backend installed at all" "$?" "0"
check "and still prints the usage rather than an error" \
  "$(grep -c '^Usage: wifi.sh' "$TMP/out")" "1"
check "and says nothing about a missing backend" \
  "$(grep -c 'No supported WiFi backend' "$TMP/out")" "0"

# Anti-vacuity: without --help that same machine really does report the error,
# so the three checks above are not passing because the fixture is inert.
HYPRSIMPLE_SYSFS_NET="$(mk_sysfs none)" PATH="$NO_BACKEND" \
  "$BASH_BIN" "$WIFI" >"$TMP/out" 2>&1 </dev/null
check "while a plain run there still reports the missing backend" \
  "$(grep -c 'No supported WiFi backend' "$TMP/out")" "1"

# An SSID is still an SSID. Only the two flags are taken as a request for help.
run "$(mk_sysfs both)" NetworkManager helpdesk
check "an SSID that merely contains 'help' is connected to" \
  "$(calls | grep -c 'connect helpdesk')" "1"

# ---- a secured network with no password given -----------------------------
#
# Reported on a new install, typing `wifi "POCO F4"`, which is the shape the
# usage line at the top of the script offers first:
#
#   passwords or encryption keys are required to access the wireless network
#     'POCO F4'
#   warning: password for '802-11-wireless-security.psk' not given in
#     'passwd-file' and nmcli cannot ask without '--ask' option
#   Error: connection activation failed: secrets were required but not provided
#
# nmcli will not prompt for a secret unless it is told it may. The script never
# told it, so the only way to join a secured network was to know to pass the
# password as a second argument.

if [[ -n $SCRIPT_BIN ]]; then
  run_on_tty "$(mk_sysfs both)" NetworkManager MyNet
  check "at a terminal, nmcli is allowed to ask for the password" \
    "$(calls | grep -c 'nmcli --ask device wifi connect MyNet')" "1"
  check "and it is not asked twice, once with the flag and once without" \
    "$(calls | grep -c 'device wifi connect')" "1"

  # The reported SSID has a space in it, which is the argument most likely to
  # be taken apart on its way through.
  run_on_tty "$(mk_sysfs both)" NetworkManager "POCO F4"
  check "an SSID with a space reaches nmcli in one piece" \
    "$(calls | grep -c 'connect POCO F4$')" "1"

  # --ask is for a missing secret, not for one already given. Passing both
  # would have nmcli prompt for parameters the caller has already supplied.
  run_on_tty "$(mk_sysfs both)" NetworkManager MyNet hunter2
  check "a password given on the command line is still passed through" \
    "$(calls | grep -c 'connect MyNet password hunter2')" "1"
  check "and nmcli is not asked to prompt as well" \
    "$(calls | grep -c -- '--ask')" "0"

  # Listing takes no secret, so it must not have grown a prompt either.
  run_on_tty "$(mk_sysfs both)" NetworkManager
  check "listing networks at a terminal asks for nothing" \
    "$(calls | grep -c -- '--ask')" "0"
else
  pass "skipped the terminal checks: no script(1) to attach one"
fi

# Without a terminal there is nobody to answer, so --ask would hang on a
# prompt no one can see. The connection is attempted as before, and the advice
# is given here rather than left to nmcli's message about passwd-file.
run "$(mk_sysfs both)" NetworkManager MyNet
check "with no terminal, nmcli is not told to prompt" \
  "$(calls | grep -c -- '--ask')" "0"
check "and the connection is still attempted" \
  "$(calls | grep -c 'nmcli device wifi connect MyNet')" "1"

NMCLI_RC=4 run "$(mk_sysfs both)" NetworkManager MyNet
check "and when it fails, the password is named as the likely reason" \
  "$(grep -c "wifi.sh 'MyNet' '<password>'" "$TMP/out")" "1"
check "while the exit status stays nmcli's own" "$(rc)" "4"

NMCLI_RC=0 run "$(mk_sysfs both)" NetworkManager MyNet
check "and a connection that works says nothing about passwords" \
  "$(grep -c 'password' "$TMP/out")" "0"
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
