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
#
# The first run, which sets supergfxctl up, is held to the same rule. Its AUR
# helper, pacman, sudo and systemctl are stubs, HOME is a temp directory, and
# the config path points into it, so nothing is built, no service is started
# and /etc is never written.

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
# tee is what the config is written through, and ln is how the stub AUR helper
# makes supergfxctl appear. Neither can change anything outside TMP here.
for tool in timeout tee ln; do
  ln -s "$(command -v "$tool")" "$TOOLS/$tool"
done

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

# Where the first run is told to look and write. Set on every run, so no case
# here can read the real ~/.local/bin or write the real /etc/supergfxd.conf.
HOME_DIR="$TMP/home"
GFX_CONF="$TMP/etc/supergfxd.conf"
SETUP_LOG="$TMP/setup-calls"
# The PATH of a machine with no supergfxctl. Filled in by arrange_setup below.
SETUP_BIN="$TMP/setup-bin"

rc=0
run_toggle() {
  : >"$LOG"; : >"$SETUP_LOG"
  PATH="${TOGGLE_PATH:-$STUB:$TOOLS}" GFX_STATE="$STATE" CALL_LOG="$LOG" \
    HOME="$HOME_DIR" HYPRSIMPLE_SUPERGFXD_CONF="$GFX_CONF" SETUP_LOG="$SETUP_LOG" \
    SETUP_BIN="$SETUP_BIN" GFX_STUB="$STUB/supergfxctl" \
    HYPRSIMPLE_CMDLINE_FILE="$CMDLINE" \
    "$BASH_BIN" "$TOGGLE" >"$TMP/out" 2>&1
  rc=$?
}
requests() { tr '\n' ' ' <"$LOG"; }
said() { grep -c -- "$1" "$TMP/out"; }
setup_calls() { grep -c -- "$1" "$SETUP_LOG"; }

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

# --- the first run, which sets supergfxctl up --------------------------------
#
# install.sh did this on every hybrid machine for a short while. It is done
# here now, by whoever runs the toggle, and each case below starts from a
# machine that has no supergfxctl.
#
# SETUP_BIN is that machine's PATH: an AUR helper, pacman, sudo and systemctl,
# all stubs, and no supergfxctl until the helper "builds" it by linking the
# stub daemon in.

arrange_setup() {
  arrange Hybrid
  rm -rf "${SETUP_BIN:?}" "${HOME_DIR:?}" "${TMP:?}/etc"
  mkdir -p "$SETUP_BIN" "$HOME_DIR/.local/bin" "$TMP/etc"
  cp "$REPO/.local/bin/hyprsimple-aur-helper.sh" "$HOME_DIR/.local/bin/"

  cat >"$SETUP_BIN/paru" <<'STUBEOF'
#!/bin/bash
printf 'paru %s\n' "$*" >>"$SETUP_LOG"
[[ -e $GFX_STATE/build_fails ]] && exit 1
[[ -e $GFX_STATE/build_noop ]] && exit 0
ln -s "$GFX_STUB" "$SETUP_BIN/supergfxctl"
STUBEOF
  cat >"$SETUP_BIN/pacman" <<'STUBEOF'
#!/bin/bash
[[ ${1:-} == -Qq && -e $GFX_STATE/has_$2 ]] && exit 0
exit 1
STUBEOF
  cat >"$SETUP_BIN/sudo" <<'STUBEOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$SETUP_LOG"
"$@"
STUBEOF
  cat >"$SETUP_BIN/systemctl" <<'STUBEOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$SETUP_LOG"
[[ -e $GFX_STATE/systemctl_fails ]] && exit 1
exit 0
STUBEOF
  chmod +x "$SETUP_BIN"/*
  local flag
  for flag in "$@"; do : >"$STATE/$flag"; done
}
run_setup() { TOGGLE_PATH="$SETUP_BIN:$TOOLS" run_toggle; }

arrange_setup
run_setup
check "with no supergfxctl, the first run exits 0" "$rc" "0"
check "and asks the AUR helper for it, with no flag that stops the helper asking" \
  "$(grep '^paru ' "$SETUP_LOG")" "paru -S supergfxctl"
check "and writes supergfxd's config" "$([[ -f $GFX_CONF ]] && echo yes || echo no)" "yes"
check "in Hybrid mode, which is how the machine was already running" \
  "$(grep -c '"mode": "Hybrid"' "$GFX_CONF" 2>/dev/null)" "1"
check "and enables and starts the service" \
  "$(setup_calls '^systemctl enable --now supergfxd$')" "1"
check "and switches nothing on that run" "$(requests)" ""
check "and says to run it again to switch" "$(said 'run toggle-hybrid-gpu.sh again')" "1"

# A config that is already there is somebody's choice of mode.
arrange_setup
printf '{\n  "mode": "Integrated"\n}\n' >"$GFX_CONF"
before="$(<"$GFX_CONF")"
run_setup
check "an existing config is left exactly as it was" "$(<"$GFX_CONF")" "$before"
check "and the service is still started" \
  "$(setup_calls '^systemctl enable --now supergfxd$')" "1"

# The build is a Rust compile and can fail, or be declined at the helper's own
# prompt. Either way nothing else may be touched.
arrange_setup build_fails
run_setup
check "a helper that fails exits 1" "$rc" "1"
check "and writes no config" "$([[ -e $GFX_CONF ]] && echo yes || echo no)" "no"
check "and calls no sudo and no systemctl" "$(setup_calls '^sudo \|^systemctl ')" "0"

arrange_setup build_noop
run_setup
check "a helper that exits 0 without installing anything still exits 1" "$rc" "1"
check "and writes no config either" "$([[ -e $GFX_CONF ]] && echo yes || echo no)" "no"
check "and starts no service" "$(setup_calls '^systemctl ')" "0"

arrange_setup
rm -f "$SETUP_BIN/paru"
run_setup
check "with no AUR helper it exits 1" "$rc" "1"
check "and names both helpers it could use" "$(said 'paru or yay')" "1"
check "and calls no sudo and no systemctl" "$(setup_calls '^sudo \|^systemctl ')" "0"

arrange_setup
rm -f "$HOME_DIR/.local/bin/hyprsimple-aur-helper.sh"
run_setup
check "with the shared helper file missing it exits 1" "$rc" "1"
check "and points at hyprsimple-update" "$(said 'hyprsimple-update')" "1"
check "and the AUR helper is not run" "$(setup_calls '^paru ')" "0"

for other in optimus-manager system76-power bbswitch bbswitch-dkms; do
  arrange_setup "has_$other"
  run_setup
  check "with $other installed it exits 1" "$rc" "1"
  check "and names $other" "$(said "$other is installed")" "1"
  check "and does not run the AUR helper ($other)" "$(setup_calls '^paru ')" "0"
done

arrange_setup systemctl_fails
run_setup
check "a service that will not start exits 1" "$rc" "1"
check "and points at its status" "$(said 'systemctl status supergfxd')" "1"
check "and does not say it is set up" "$(said 'is set up in Hybrid mode')" "0"

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
