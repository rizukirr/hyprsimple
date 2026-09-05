#!/bin/bash

# Usage: keyboard-brightness.sh <up|down|cycle>
# Controls keyboard backlight via brightnessctl
#
# The device used to be the literal string "kbd_backlight". brightnessctl
# matches -d against the exact device name and does no partial matching, and a
# real keyboard backlight is always vendor prefixed: tpacpi::kbd_backlight,
# asus::kbd_backlight, dell::kbd_backlight, smc::kbd_backlight. So the name it
# asked for matched nothing anywhere, brightnessctl exited 1, and -q meant it
# said nothing about it. Both keys did nothing on every machine.
#
# Found by globbing sysfs, which is where the names come from, the way wifi.sh
# finds its interface. Overridable so the suite can arrange a machine with a
# backlight and one without.

LEDS_DIR="${HYPRSIMPLE_LEDS_DIR:-/sys/class/leds}"
STEP="33%"

find_backlight() {
  local led
  for led in "$LEDS_DIR"/*kbd_backlight; do
    [[ -e $led ]] || continue
    basename "$led"
    return 0
  done
}

usage() {
  echo "Usage: $(basename "$0") <up|down|cycle>" >&2
  exit 1
}

case "${1:-}" in
up | down | cycle) ;;
*) usage ;;
esac

DEVICE=$(find_backlight)

if [[ -z $DEVICE ]]; then
  # Said rather than swallowed. Silence is what let the old device name go
  # unnoticed for as long as it did.
  notify-send -u low -t 2000 "Keyboard backlight" "This machine has no keyboard backlight"
  exit 1
fi

case "$1" in
up)
  brightnessctl -d "$DEVICE" set "${STEP}+" -q
  ;;
down)
  brightnessctl -d "$DEVICE" set "${STEP}-" -q
  ;;
cycle)
  CURRENT=$(brightnessctl -d "$DEVICE" get 2>/dev/null || echo 0)
  MAX=$(brightnessctl -d "$DEVICE" max 2>/dev/null || echo 0)
  if [[ $CURRENT -ge $MAX ]]; then
    brightnessctl -d "$DEVICE" set 0 -q
  else
    brightnessctl -d "$DEVICE" set "${STEP}+" -q
  fi
  ;;
esac
