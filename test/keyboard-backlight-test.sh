#!/bin/bash
# XF86KbdBrightnessUp and XF86KbdBrightnessDown did nothing on any machine.
#
# keyboard-brightness.sh asked brightnessctl for a device named literally
# "kbd_backlight":
#
#   DEVICE="kbd_backlight"
#   brightnessctl -d "$DEVICE" set "33%+" -q
#
# brightnessctl matches -d against the exact device name and does no partial
# matching, measured directly:
#
#   -d input4::capslock   rc=0
#   -d capslock           rc=1  Device 'capslock' not found.
#   -d kbd_backlight      rc=1  Device 'kbd_backlight' not found.
#
# A real keyboard backlight is always vendor prefixed: tpacpi::kbd_backlight on
# ThinkPads, asus::, dell::, smc:: elsewhere. So the name it asked for matched
# nothing anywhere, and -q meant brightnessctl said nothing about it while
# exiting 1. Two keys, silently dead, on every install.
#
# Same shape as the bluetooth adapter in #87: an identifier hardcoded to one
# value that reality does not use.
#
# The LED directory is overridable, so a machine with a backlight and one
# without are both arranged here without needing either.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/.local/bin/keyboard-brightness.sh"
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
cat >"$STUB/brightnessctl" <<'STUBEOF'
#!/bin/bash
# The arguments are saved before the loop below consumes them. An earlier
# version read "$*" after shifting it all away, so it never answered get or
# max, and the cycle checks were passing without reading either.
args="$*"
printf 'brightnessctl %s\n' "$args" >>"$CALL_LOG"
# Only the device the test says exists is accepted, the way the real one
# behaves: an exact name or nothing.
dev=""
while (( $# )); do [[ $1 == -d ]] && dev=$2; shift; done
[[ $dev == "${REAL_DEVICE:-}" ]] || { echo "Device '$dev' not found." >&2; exit 1; }
case "$args" in *get*) echo "${CUR:-0}" ;; *max*) echo "${MAX:-100}" ;; esac
STUBEOF
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf 'notify-send %s\n' "$*" >>"$CALL_LOG"
STUBEOF
chmod +x "$STUB"/*

# A sysfs shape with whatever LEDs the test names.
mk_leds() {
  rm -rf "${TMP:?}/leds"; mkdir -p "$TMP/leds"
  local led
  for led in "$@"; do mkdir -p "$TMP/leds/$led"; done
}
run() {
  : >"$LOG"
  CALL_LOG="$LOG" HYPRSIMPLE_LEDS_DIR="$TMP/leds" REAL_DEVICE="${2:-}" \
    CUR="${3:-0}" MAX="${4:-100}" \
    PATH="$STUB:/usr/bin:/bin" bash "$SCRIPT" "$1" >"$TMP/out" 2>"$TMP/err"
  printf '%s' "$?" >"$TMP/rc"
}

# --- the vendor prefixes that actually occur --------------------------------

for dev in tpacpi::kbd_backlight asus::kbd_backlight dell::kbd_backlight \
  smc::kbd_backlight platform::kbd_backlight kbd_backlight; do
  mk_leds "input4::capslock" "$dev"
  run up "$dev"
  check "up finds $dev" "$(grep -c -- "-d $dev set 33%+" "$LOG")" "1"
  run down "$dev"
  check "down finds $dev" "$(grep -c -- "-d $dev set 33%-" "$LOG")" "1"
done

# --- a machine with no keyboard backlight -----------------------------------

mk_leds "input4::capslock" "phy0-led" "mmc0::"
run up ""
check "with no backlight nothing is set" "$(grep -c 'brightnessctl' "$LOG")" "0"
check "and it says so rather than failing in silence" \
  "$(grep -c 'no keyboard backlight' "$LOG")" "1"
check "and exits non-zero" "$(cat "$TMP/rc")" "1"

# --- cycle ------------------------------------------------------------------

mk_leds "tpacpi::kbd_backlight"
run cycle tpacpi::kbd_backlight 100 100
check "cycle at maximum turns it off" \
  "$(grep -c -- '-d tpacpi::kbd_backlight set 0' "$LOG")" "1"
run cycle tpacpi::kbd_backlight 0 100
check "cycle below maximum steps up" \
  "$(grep -c -- '-d tpacpi::kbd_backlight set 33%+' "$LOG")" "1"

# --- an unknown argument ----------------------------------------------------

mk_leds "tpacpi::kbd_backlight"
run bogus tpacpi::kbd_backlight
check "an unknown argument exits non-zero" "$(cat "$TMP/rc")" "1"
check "and prints usage on stderr" "$(grep -c 'Usage: keyboard-brightness.sh' "$TMP/err")" "1"
check "and touches no device" "$(grep -c 'brightnessctl' "$LOG")" "0"

# --- the old literal is gone ------------------------------------------------

code_of() { sed 's/#.*//' "$1"; }
check "the script no longer names a bare kbd_backlight device" \
  "$(code_of "$SCRIPT" | grep -c 'DEVICE="kbd_backlight"')" "0"
# Named lines, not a count. I guessed a count in #92 and guessed wrong there
# too, so this asserts the two lines that must survive the stripper.
check "stripping comments leaves the up branch" \
  "$(code_of "$SCRIPT" | grep -c 'set "\${STEP}+" -q')" "2"
check "and the device lookup" \
  "$(code_of "$SCRIPT" | grep -c 'for led in "\$LEDS_DIR"/\*kbd_backlight')" "1"

# --- brightnessctl really is exact-match, which is the whole premise --------

if command -v brightnessctl >/dev/null 2>&1; then
  real=$(brightnessctl --list 2>/dev/null | sed -n "s/^Device '\(.*\)' of class 'leds':$/\1/p" | head -1)
  if [[ -n $real ]]; then
    if brightnessctl -d "$real" get >/dev/null 2>&1; then
      pass "the real brightnessctl accepts an exact device name ($real)"
    else
      fail "the real brightnessctl rejected $real, so this suite's premise is wrong"
    fi
    partial=${real##*::}
    if [[ $partial != "$real" ]]; then
      if brightnessctl -d "$partial" get >/dev/null 2>&1; then
        fail "the real brightnessctl matched the partial name $partial, so the bug was not what this says"
      else
        pass "and rejects the partial name $partial, which is why the old device string never matched"
      fi
    fi
  fi
fi

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
