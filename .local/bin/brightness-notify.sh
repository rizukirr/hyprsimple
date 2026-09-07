#!/bin/bash
# Show current brightness using dunst

NOTIFY_ID=9998

# Nothing rather than a level, when brightnessctl cannot answer.
#
# This divided by max without looking at it. On a machine brightnessctl has no
# device on, both reads come back empty, and bash reported
#
#   line 9: (current * 100) / max: division by 0 (error token is "max")
#
# on stderr, where a keybind sends it nowhere, and then showed "Brightness: %"
# with an empty bar. A notification with no number in it is worse than none.
get_brightness() {
  local current max
  current=$(brightnessctl get 2>/dev/null)
  max=$(brightnessctl max 2>/dev/null)
  [[ $current =~ ^[0-9]+$ && $max =~ ^[0-9]+$ ]] || return 1
  (( max > 0 )) || return 1
  printf '%s' "$(((current * 100) / max))"
}

# printf with no arguments prints its format string once, so
# `printf 'X%.0s' $(seq 1 0)` yields one X rather than none. That put a filled
# block in the bar at 0 and an empty one at 100, and made the bar 21 characters
# wide at both ends instead of 20. A loop has no such edge.
repeat_char() {
  local count=$1 char=$2 i out=""
  for ((i = 0; i < count; i++)); do out+="$char"; done
  printf '%s' "$out"
}

show_notification() {
  brightness=$1
  filled=$((brightness / 5))
  empty=$((20 - filled))
  bar="$(repeat_char "$filled" '█')$(repeat_char "$empty" '░')"
  notify-send -u low -t 1500 -r $NOTIFY_ID "Brightness: $brightness%" "$bar"
}

if ! level=$(get_brightness); then
  notify-send -u low -t 1500 -r $NOTIFY_ID "Brightness" "Could not read the current brightness"
  exit 1
fi

show_notification "$level"
