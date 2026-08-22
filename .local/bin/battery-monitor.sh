#!/bin/bash

# Battery notification script - reduce brightness when battery is low
# Designed to be run by systemd timer every 30 seconds

BATTERY_THRESHOLD=(20 15 10 5 3)
# Brightness to drop to once the battery reaches the first threshold. Fixed on
# purpose: dimming hard and early buys more runtime than stepping down slowly.
LOW_BATTERY_BRIGHTNESS=5
FLAG_FILE="/tmp/battery-notification-flag"

get_battery_percentage() {
  upower -i "$(upower -e | grep 'BAT')" |
    awk -F: '/percentage/ {
      gsub(/[%[:space:]]/, "", $2);
      val=$2;
      printf("%d\n", (val+0.5))
      exit
    }'
}

get_battery_state() {
  upower -i "$(upower -e | grep 'BAT')" | grep -E "state" | awk '{print $2}'
}

BATTERY_LEVEL=$(get_battery_percentage)
BATTERY_STATE=$(get_battery_state)

if [[ "$BATTERY_STATE" == "discharging" ]]; then
  for threshold in "${BATTERY_THRESHOLD[@]}"; do
    if [[ "$BATTERY_LEVEL" -le "$threshold" ]]; then
      brightnessctl set "${LOW_BATTERY_BRIGHTNESS}"%

      # Send notification only once per threshold using flag file
      if [[ ! -f "$FLAG_FILE" ]] || [[ $(cat "$FLAG_FILE" 2>/dev/null) != "$threshold" ]]; then
        dunstify -u critical "Battery Low" "Battery at ${BATTERY_LEVEL}%, brightness reduced to ${LOW_BATTERY_BRIGHTNESS}%"
        echo "$threshold" >"$FLAG_FILE"
      fi
    fi
  done
else
  # Clear flag when charging/charged to allow new notifications on next discharge
  rm -f "$FLAG_FILE"
fi
