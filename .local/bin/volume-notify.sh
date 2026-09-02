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

show_notification() {
  vol=$1
  if [[ "$vol" == "muted" ]]; then
    notify-send -u low -t 1500 -r $NOTIFY_ID "Volume" "Muted 🔇"
  else
    filled=$((vol / 5))
    empty=$((20 - filled))
    bar="$(printf '█%.0s' $(seq 1 $filled))$(printf '░%.0s' $(seq 1 $empty))"
    notify-send -u low -t 1500 -r $NOTIFY_ID "Volume: $vol%" "$bar"
  fi
}

show_notification "$(get_volume)"
