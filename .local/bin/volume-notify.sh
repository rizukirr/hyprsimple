#!/bin/bash

# Show current PipeWire volume using dunst

NOTIFY_ID=9999

get_volume() {
  vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@)
  level=$(echo "$vol" | awk '{print int($2*100)}')
  if echo "$vol" | grep -q MUTED; then
    echo "muted"
  else
    echo "$level"
  fi
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
  vol=$1
  if [[ "$vol" == "muted" ]]; then
    notify-send -u low -t 1500 -r $NOTIFY_ID "Volume" "Muted 🔇"
  else
    filled=$((vol / 5))
    empty=$((20 - filled))
    bar="$(repeat_char "$filled" '█')$(repeat_char "$empty" '░')"
    notify-send -u low -t 1500 -r $NOTIFY_ID "Volume: $vol%" "$bar"
  fi
}

show_notification "$(get_volume)"
