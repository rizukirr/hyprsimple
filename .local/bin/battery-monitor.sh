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
  # The lowest threshold the battery has fallen past, not every threshold it is
  # under. Acting inside the loop meant one 9% reading dimmed the screen three
  # times and sent three identical notifications, because the flag file only
  # ever holds the last threshold written, so the next iteration compared
  # against a different number and fired again. At 2% it was five.
  #
  # Comparing rather than taking the last match, which would be shorter and
  # would rely on BATTERY_THRESHOLD staying in descending order. Nothing states
  # that invariant and nothing enforces it.
  crossed=""
  for threshold in "${BATTERY_THRESHOLD[@]}"; do
    if [[ "$BATTERY_LEVEL" -le "$threshold" ]] &&
      { [[ -z $crossed ]] || [[ "$threshold" -lt "$crossed" ]]; }; then
      crossed="$threshold"
    fi
  done

  if [[ -n $crossed ]]; then
    brightnessctl set "${LOW_BATTERY_BRIGHTNESS}"%

    # Once per crossing. Falling into a lower band writes a new value here and
    # so notifies again, which is the escalation this file was always for.
    if [[ ! -f "$FLAG_FILE" ]] || [[ $(cat "$FLAG_FILE" 2>/dev/null) != "$crossed" ]]; then
      notify-send -u critical "Battery Low" "Battery at ${BATTERY_LEVEL}%, brightness reduced to ${LOW_BATTERY_BRIGHTNESS}%"
      echo "$crossed" >"$FLAG_FILE"
    fi
  fi
else
  # Clear flag when charging/charged to allow new notifications on next discharge
  rm -f "$FLAG_FILE"
fi
