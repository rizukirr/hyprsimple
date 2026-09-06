#!/bin/bash
# The installer enables a deny-incoming firewall and skipped the one warning
# that exists for it.
#
#   sudo ufw --force enable
#
# `ufw enable` normally asks
#
#   Command may disrupt existing ssh connections. Proceed with operation (y|n)?
#
# and --force is exactly what skips that question, which is checked below
# against ufw's own source rather than taken on trust. Skipping it is right for
# a local install. It is wrong when the installer is itself running over ssh:
# "deny incoming" blocks the next connection, so the machine becomes
# unreachable the moment the session ends, and the warning that would have said
# so was the thing suppressed.
#
# The firewall itself is a documented feature, so the posture is not changed
# here. Only the case where the installer cuts its own connection.
#
# Nothing here runs ufw or sudo. setup_firewall is taken out of the installer
# and run with both stubbed to a log.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

fn=$(sed -n '/^setup_firewall() {/,/^}/p' "$INSTALL")
if [[ $(printf '%s\n' "$fn" | grep -c .) -lt 10 ]]; then
  fail "extracted $(printf '%s\n' "$fn" | grep -c .) lines of setup_firewall, so this is reading the wrong thing"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "extracted setup_firewall from the installer"

STUB="$TMP/bin"; mkdir -p "$STUB"
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALL_LOG"
STUBEOF
cat >"$STUB/ufw" <<'STUBEOF'
#!/bin/bash
printf 'ufw %s\n' "$*" >>"$CALL_LOG"
STUBEOF
chmod +x "$STUB"/*

LOG="$TMP/calls"
run_firewall() {
  : >"$LOG"
  env -u SSH_CONNECTION CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" "$@" bash -c "
    GREEN=; YELLOW=; NC=
    $fn
    setup_firewall
  " >/dev/null 2>&1
}

# --- a local install is unchanged ---------------------------------------------

run_firewall
check "a local install denies incoming" \
  "$(grep -c 'ufw default deny incoming' "$LOG")" "1"
check "and allows outgoing" \
  "$(grep -c 'ufw default allow outgoing' "$LOG")" "1"
check "and opens LocalSend" "$(grep -c 'ufw allow 53317' "$LOG")" "2"
check "and enables the firewall" "$(grep -c 'ufw --force enable' "$LOG")" "1"
check "and does not open ssh, nobody having asked for it" \
  "$(grep -c 'ufw allow ssh' "$LOG")" "0"

# --- an install running over ssh keeps its own way back in --------------------

run_firewall env SSH_CONNECTION="10.0.0.5 51234 10.0.0.9 22"
check "an install over ssh keeps ssh reachable" \
  "$(grep -c 'ufw allow ssh' "$LOG")" "1"
check "before enabling, not after, or the gap is the whole problem" \
  "$(( $(grep -n 'ufw allow ssh' "$LOG" | cut -d: -f1) < $(grep -n 'ufw --force enable' "$LOG" | cut -d: -f1) ? 1 : 0 ))" "1"
check "and the rest of the posture is the same" \
  "$(grep -c 'ufw default deny incoming' "$LOG")" "1"
check "and it still enables the firewall" \
  "$(grep -c 'ufw --force enable' "$LOG")" "1"

# --- the reason the warning matters -------------------------------------------
#
# Read out of ufw itself, so this suite is not asserting a claim about ufw that
# ufw does not make.
# A glob rather than parsing ls, which is the one finding class this project
# has actually shipped as a bug.
UFW_SRC=""
for candidate in /usr/lib/python3*/site-packages/ufw/frontend.py; do
  [[ -f $candidate ]] && { UFW_SRC="$candidate"; break; }
done
if [[ -z $UFW_SRC ]]; then
  pass "ufw's source is not here, so its prompt cannot be quoted"
else
  # At least once, not exactly once: ufw wraps the sentence across two source
  # lines and grep -c counts both.
  hits=$(grep -c 'disrupt existing ssh connections' "$UFW_SRC")
  check "ufw does warn about disrupting ssh, which --force skips" \
    "$(( hits >= 1 ? 1 : 0 ))" "1"
fi

# --- and the installer still says what it did ---------------------------------

code_of() { sed 's/#.*//' "$1"; }
CODE="$TMP/install.code"
code_of "$INSTALL" >"$CODE"
check "stripping comments leaves the installer's code behind" \
  "$(grep -c '^setup_firewall()' "$CODE")" "1"
check "the ssh case is guarded on SSH_CONNECTION, not on sshd running" \
  "$(grep -c 'SSH_CONNECTION' "$CODE")" "1"
check "and tells the user how to close it again" \
  "$(grep -c 'ufw delete allow ssh' "$CODE")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
