#!/bin/bash
# toggle-hybrid-gpu.sh asks supergfxd to turn the discrete GPU off or on, and
# supergfxd cannot run here: it needs a hybrid laptop and a system bus. So the
# daemon is a stub that follows the rules the real one was seen to follow.
#
#   to or from Hybrid     accepted, and pending until the next logout
#   Integrated and Vfio   switch at once
#   Vfio to Hybrid        declined with "You must change to Integrated before
#                         you can change to Hybrid"
#
# The last row is the one this script exists for. A laptop was found in Vfio
# with its card unusable, and `supergfxctl -m Hybrid` answered with that line
# and nothing else. The stub exits 0 when it declines, which is the case a
# check of the exit status alone would report as a switch. The toggle reads the
# mode and the pending action back instead, and the checks below hold it to
# that.
#
# The real supergfxctl is never reachable from here. PATH holds the stub and a
# directory with `timeout` in it, and nothing else, so a machine that has
# supergfxctl installed cannot have its GPU mode changed by running this suite.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOGGLE="$REPO/.local/bin/toggle-hybrid-gpu.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

if [[ -f $TOGGLE ]]; then
  pass "the toggle exists"
else
  fail "toggle-hybrid-gpu.sh is missing, so nothing below is testing it"
fi

# Resolved before PATH is narrowed, since neither is a builtin.
BASH_BIN="$(command -v bash)"
TOOLS="$TMP/tools"; mkdir -p "$TOOLS"
ln -s "$(command -v timeout)" "$TOOLS/timeout"

STUB="$TMP/bin"; mkdir -p "$STUB"
STATE="$TMP/state"; mkdir -p "$STATE"
LOG="$TMP/calls"
CMDLINE="$TMP/cmdline"

# Builtins only, because PATH has nothing else on it.
cat >"$STUB/supergfxctl" <<'STUBEOF'
#!/bin/bash
mode="$(<"$GFX_STATE/mode")"
case "${1:-}" in
  -g)
    [[ -e $GFX_STATE/silent ]] && exit 1
    printf '%s\n' "$mode"
    ;;
  -p)
    if [[ -e $GFX_STATE/pending ]]; then
      printf 'Logout required to complete mode change\n'
    else
      printf 'No action required\n'
    fi
    ;;
  -m)
    printf -- '-m %s\n' "$2" >>"$CALL_LOG"
    if [[ -e $GFX_STATE/fail_m ]]; then
      printf 'stub: the bus refused the call\n' >&2
      exit 1
    fi
    if [[ -e $GFX_STATE/stuck ]]; then
      printf 'stub: not switching, and saying why\n'
      exit 0
    fi
    if [[ -e $GFX_STATE/instant ]]; then
      printf '%s\n' "$2" >"$GFX_STATE/mode"
    elif [[ $mode == Vfio && $2 == Hybrid ]]; then
      printf 'You must change to Integrated before you can change to Hybrid\n'
    elif [[ $mode == Hybrid || $2 == Hybrid ]]; then
      printf '%s\n' "$2" >"$GFX_STATE/pending"
      printf 'Graphics mode changed to %s. Logout required to complete mode change\n' "$2"
    else
      printf '%s\n' "$2" >"$GFX_STATE/mode"
    fi
    ;;
esac
exit 0
STUBEOF
chmod +x "$STUB/supergfxctl"

# Start from a named mode with nothing pending and no behaviour switched on.
# The flags after the mode are the stub's: silent, fail_m, stuck, instant.
arrange() {
  rm -rf "${STATE:?}"; mkdir -p "$STATE"
  printf '%s\n' "$1" >"$STATE/mode"
  shift
  local flag
  for flag in "$@"; do : >"$STATE/$flag"; done
  : >"$CMDLINE"
}

rc=0
run_toggle() {
  : >"$LOG"
  PATH="${TOGGLE_PATH:-$STUB:$TOOLS}" GFX_STATE="$STATE" CALL_LOG="$LOG" \
    HYPRSIMPLE_CMDLINE_FILE="$CMDLINE" \
    "$BASH_BIN" "$TOGGLE" >"$TMP/out" 2>&1
  rc=$?
}
requests() { tr '\n' ' ' <"$LOG"; }
said() { grep -c -- "$1" "$TMP/out"; }

# --- the two directions ------------------------------------------------------

arrange Hybrid
run_toggle
check "from Hybrid it asks for Integrated" "$(requests)" "-m Integrated "
check "and exits 0" "$rc" "0"
check "and says the switch was requested" "$(said 'Integrated mode requested')" "1"
# Once. supergfxctl narrates an accepted request in nearly the same words as
# its pending action, and printing both told the user the same thing twice.
check "and passes on what supergfxd says is pending, once" "$(said 'Logout required')" "1"
check "and does not claim it switched, since the mode has not changed" "$(said 'switched')" "0"

arrange Integrated
run_toggle
check "from Integrated it asks for Hybrid" "$(requests)" "-m Hybrid "
check "and exits 0 there too" "$rc" "0"

# --- a switch that lands at once is reported as one --------------------------

arrange Hybrid instant
run_toggle
check "a mode that changed at once is reported as switched" "$(said 'switched to Integrated mode')" "1"
check "and not as merely requested" "$(said 'requested')" "0"

# --- Vfio, the dead end ------------------------------------------------------

arrange Vfio
run_toggle
check "from Vfio it asks for Integrated and then Hybrid, in that order" \
  "$(requests)" "-m Integrated -m Hybrid "
check "and exits 0" "$rc" "0"
check "and reports Hybrid as requested" "$(said 'Hybrid mode requested')" "1"

# If the first hop does not land, asking for Hybrid would only be declined the
# same way the bare command was.
arrange Vfio stuck
run_toggle
check "a first hop that did not land stops the chain" "$(requests)" "-m Integrated "
check "and exits 1" "$rc" "1"
check "and shows what supergfxctl answered, which is the reason" "$(said 'saying why')" "1"

# --- a request supergfxd declines with exit status 0 -------------------------

arrange Hybrid stuck
run_toggle
check "a request that changed nothing and left nothing pending exits 1" "$rc" "1"
check "and is not reported as switched" "$(said 'switched')" "0"
check "and is not reported as requested" "$(said 'requested')" "0"
check "and says supergfxd did not take it" "$(said 'did not take the switch')" "1"
check "and shows what supergfxctl answered" "$(said 'saying why')" "1"

# --- modes this toggle does not own ------------------------------------------

arrange AsusMuxDgpu
run_toggle
check "an unknown mode exits 1" "$rc" "1"
check "and sends no request" "$(requests)" ""
check "and names the mode" "$(said 'AsusMuxDgpu')" "1"

# --- supergfxd not answering -------------------------------------------------

arrange Hybrid silent
run_toggle
check "a silent daemon exits 1" "$rc" "1"
check "and sends no request" "$(requests)" ""
check "and points at the service" "$(said 'systemctl status supergfxd')" "1"

# --- supergfxctl not installed -----------------------------------------------

arrange Hybrid
TOGGLE_PATH="$TOOLS" run_toggle
check "without supergfxctl it exits 1" "$rc" "1"
check "and sends no request" "$(requests)" ""
check "and says how to install it" "$(said 'S supergfxctl')" "1"
check "and how to start the service" "$(said 'systemctl enable --now supergfxd')" "1"

# --- the kernel command line -------------------------------------------------

arrange Integrated
printf 'root=/dev/mapper/root rw module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm quiet\n' >"$CMDLINE"
run_toggle
check "module_blacklist= naming nvidia refuses the switch to Hybrid" "$rc" "1"
check "and sends no request" "$(requests)" ""
check "and names the parameter" "$(said 'module_blacklist=')" "1"

# The parameter stops the driver loading. Turning the card off needs no driver.
arrange Hybrid
printf 'root=/dev/mapper/root rw module_blacklist=nvidia,nvidia_modeset,nvidia_uvm,nvidia_drm quiet\n' >"$CMDLINE"
run_toggle
check "the same parameter does not stop the switch to Integrated" "$(requests)" "-m Integrated "
check "which exits 0" "$rc" "0"

arrange Integrated
printf 'root=/dev/mapper/root rw modprobe.blacklist=nvidia_drm,nvidia_modeset,nvidia_uvm,nvidia quiet\n' >"$CMDLINE"
run_toggle
check "modprobe.blacklist= naming nvidia still sends the request" "$(requests)" "-m Hybrid "
check "and exits 0" "$rc" "0"
check "and warns about the parameter" "$(said 'modprobe.blacklist=')" "1"

# A blacklist of something else is not this script's business.
arrange Integrated
printf 'root=/dev/mapper/root rw module_blacklist=nouveau quiet\n' >"$CMDLINE"
run_toggle
check "a blacklist that does not name nvidia is ignored" "$(requests)" "-m Hybrid "

# --- supergfxctl itself failing ----------------------------------------------

arrange Hybrid fail_m
run_toggle
check "a failed request exits 1" "$rc" "1"
check "and passes supergfxctl's own message through" "$(said 'the bus refused the call')" "1"
check "and does not claim a switch" "$(said 'switched')" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
