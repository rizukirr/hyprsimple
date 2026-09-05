#!/bin/bash
# setup_network repointed /etc/resolv.conf at systemd-resolved's stub without
# ever asking whether systemd-resolved was running.
#
# Nothing in hyprsimple installs or enables it. It is not in packages.txt, and
# Arch does not enable it on a stock install. On such a machine
# /run/systemd/resolve/stub-resolv.conf does not exist, so /etc/resolv.conf
# became a dangling symlink and the host had no DNS at all. Not only afterwards:
# setup_network runs at install.sh:463, and the script still has a release tag
# to fetch over the network and two packages to install after that.
#
# The same repository already knew. setup-dns.sh:6 refuses to touch DNS when
# resolved is not running, and says so in a comment. This did the far more
# destructive version of the same operation with no check at all.
#
# This machine has resolved enabled, courtesy of CachyOS, which is why it never
# showed up here. The paths are overridable so both answers can be arranged
# without touching the DNS of whatever is running the suite.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

FUNCS="$TMP/funcs.sh"
sed -n '/^setup_network() {/,/^}/p' "$REPO/install.sh" >"$FUNCS"
for marker in 'setup_network() {' 'HYPRSIMPLE_RESOLV_CONF' 'is-active --quiet systemd-resolved'; do
  if grep -qF -- "$marker" "$FUNCS"; then
    pass "extracted source contains $marker"
  else
    fail "extracted source is missing $marker, so nothing below is testing install.sh"
  fi
done

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"

# systemctl answers is-active from the test, and `enable --now` creates the stub
# only when the test says starting resolved works, which is the whole variable.
cat >"$STUB/systemctl" <<'STUBEOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
  *"is-active"*"systemd-resolved"*) [[ ${RESOLVED_ACTIVE:-no} == yes ]] && exit 0; exit 3 ;;
  *"enable --now systemd-resolved"*)
    if [[ ${RESOLVED_STARTABLE:-no} == yes ]]; then
      printf 'nameserver 127.0.0.53\n' >"$HYPRSIMPLE_RESOLVED_STUB"; exit 0
    fi
    exit 1 ;;
esac
exit 0
STUBEOF
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
"$@"
STUBEOF
chmod +x "$STUB"/*

run_setup_network() {
  rm -rf "$TMP/root"; mkdir -p "$TMP/root/run"
  : >"$LOG"
  # A resolv.conf that something else already manages, so the test can tell
  # "left alone" apart from "replaced".
  printf 'nameserver 192.0.2.1\n' >"$TMP/root/resolv.conf"
  [[ ${1:-no} == yes ]] && printf 'nameserver 127.0.0.53\n' >"$TMP/root/run/stub-resolv.conf"
  CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" \
    HYPRSIMPLE_RESOLV_CONF="$TMP/root/resolv.conf" \
    HYPRSIMPLE_RESOLVED_STUB="$TMP/root/run/stub-resolv.conf" \
    RESOLVED_ACTIVE="${2:-no}" RESOLVED_STARTABLE="${3:-no}" \
    bash -c '
      set -uo pipefail
      RED=""; GREEN=""; YELLOW=""; NC=""
      source "'"$FUNCS"'"
      setup_network
    ' >"$TMP/out" 2>&1
}

resolv_state() {
  local f="$TMP/root/resolv.conf"
  if [[ -L $f ]]; then
    [[ -e $f ]] && echo "symlink-live" || echo "symlink-DANGLING"
  elif [[ -f $f ]]; then echo "regular-file"
  else echo "missing"; fi
}

# --- resolved already running: the original intent still happens -------------

run_setup_network yes yes
check "with resolved running the stub is linked" "$(resolv_state)" "symlink-live"
check "and the link resolves to the stub" \
  "$(cat "$TMP/root/resolv.conf")" "nameserver 127.0.0.53"
check "and it does not try to enable an already running unit" \
  "$(grep -c 'enable --now systemd-resolved' "$LOG")" "0"

# --- resolved not running but startable: enable it, then link ----------------

run_setup_network no no yes
check "a stopped but startable resolved is enabled" \
  "$(grep -c 'enable --now systemd-resolved' "$LOG")" "1"
check "and the stub is linked once it is up" "$(resolv_state)" "symlink-live"

# --- resolved not running and not startable: leave DNS alone -----------------

run_setup_network no no no
check "an unstartable resolved leaves resolv.conf as a real file" \
  "$(resolv_state)" "regular-file"
check "and the existing nameserver is untouched" \
  "$(cat "$TMP/root/resolv.conf")" "nameserver 192.0.2.1"
check "and the reason is stated" \
  "$(grep -c 'is being left alone' "$TMP/out")" "1"
check "and it does not claim the network was configured" \
  "$(grep -c 'Network configured' "$TMP/out")" "0"

# The point of the whole change: never leave a dangling resolv.conf.
for scenario in "no no no" "no no yes" "yes yes yes"; do
  # shellcheck disable=SC2086  # three positional arguments, deliberately split
  run_setup_network $scenario
  if [[ $(resolv_state) == "symlink-DANGLING" ]]; then
    fail "scenario '$scenario' left /etc/resolv.conf dangling, which is no DNS"
  else
    pass "scenario '$scenario' never leaves resolv.conf dangling"
  fi
done

# The boot-hang unit is still disabled in every case, which is the other half of
# what this function is for.
check "systemd-networkd-wait-online is still disabled" \
  "$(grep -c 'disable systemd-networkd-wait-online' "$LOG")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
