#!/bin/bash
# Show current brightness using dunst

NOTIFY_ID=9998

get_brightness() {
  current=$(brightnessctl get)
  max=$(brightnessctl max)
  level=$(((current * 100) / max))
  echo "$level"
}

show_notification() {
  brightness=$1
  filled=$((brightness / 5))
  empty=$((20 - filled))
  bar="$(printf '█%.0s' $(seq 1 $filled))$(printf '░%.0s' $(seq 1 $empty))"
  notify-send -u low -t 1500 -r $NOTIFY_ID "Brightness: $brightness%" "$bar"
}

show_notification "$(get_brightness)"
