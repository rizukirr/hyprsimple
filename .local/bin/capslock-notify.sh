#!/bin/bash

# Find capslock LED sysfs path
CAPS_LED=""
for led in /sys/class/leds/input*::capslock; do
  [ -r "$led/brightness" ] && CAPS_LED="$led/brightness" && break
done

if [ -z "$CAPS_LED" ]; then
  echo "No capslock LED found in sysfs, falling back to hyprctl" >&2
  check_capslock() {
    hyprctl devices -j | jq -r '.keyboards[] | select(.main == true) | .capsLock'
  }
  read_state() { check_capslock; }
else
  read_state() {
    local val
    read -r val < "$CAPS_LED"
    [ "$val" = "1" ] && echo "true" || echo "false"
  }
fi

# Initialize state
previous_state=$(read_state)

# Poll for capslock state changes
while true; do
  current_state=$(read_state)

  if [ "$current_state" != "$previous_state" ]; then
    if [ "$current_state" = "true" ]; then
      notify-send -u normal -t 2000 "Caps Lock" "ON"
    else
      notify-send -u normal -t 2000 "Caps Lock" "OFF"
    fi
    previous_state="$current_state"
  fi

  sleep 0.5
done
