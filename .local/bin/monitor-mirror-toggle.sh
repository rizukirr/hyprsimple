#!/bin/bash

# Toggle between extended and mirror mode
# Auto-detects primary (built-in) and external monitors
#
# Usage: monitor-mirror-toggle.sh [on|off|toggle]
#   on     - force mirror mode
#   off    - force extended mode
#   toggle - flip current mode (default)
#
# "on" is used by the monitor.added handler in hypr/autostart.lua so an
# external display (projector) mirrors the laptop screen by default.

MODE="${1:-toggle}"
QUIET="${2:-}"

case "$MODE" in
on | off | toggle) ;;
*)
  echo "Usage: $(basename "$0") [on|off|toggle]" >&2
  exit 2
  ;;
esac

PRIMARY=$(hyprctl monitors -j | jq -r '.[] | select(.name | test("^eDP")) | .name' | head -1)
EXTERNAL=$(hyprctl monitors -j | jq -r '.[] | select(.name | test("^eDP") | not) | .name' | head -1)

if [[ -z $EXTERNAL ]]; then
  [[ $QUIET == "quiet" ]] || notify-send "Monitor Mode" "No external monitor detected"
  exit 1
fi

if [[ -z $PRIMARY ]]; then
  [[ $QUIET == "quiet" ]] || notify-send "Monitor Mode" "No built-in (eDP) display detected"
  exit 1
fi

mirror_on() {
  hyprctl keyword monitor "$EXTERNAL,preferred,auto,1,mirror,$PRIMARY"
  notify-send "Monitor Mode" "Mirror mode enabled"
}

mirror_off() {
  hyprctl keyword monitor "$EXTERNAL,preferred,auto,1"
  notify-send "Monitor Mode" "Extended display enabled"
}

is_mirrored() {
  hyprctl monitors | grep -A 5 "$EXTERNAL" | grep -q "mirror of $PRIMARY"
}

case "$MODE" in
on) mirror_on ;;
off) mirror_off ;;
toggle)
  if is_mirrored; then
    mirror_off
  else
    mirror_on
  fi
  ;;
esac
