#!/bin/bash

# Cycle through available audio output devices

sinks=$(pactl -f json list sinks | jq '[.[] | select((.ports | length == 0) or ([.ports[]? | .availability != "not available"] | any))]')
sinks_count=$(echo "$sinks" | jq '. | length')

if (( sinks_count == 0 )); then
  notify-send "Audio" "No audio devices found"
  exit 1
fi

current_sink_name=$(pactl get-default-sink)
current_sink_index=$(echo "$sinks" | jq -r --arg name "$current_sink_name" 'map(.name) | index($name)')

if [[ $current_sink_index != "null" ]]; then
  next_sink_index=$(((current_sink_index + 1) % sinks_count))
else
  next_sink_index=0
fi

next_sink=$(echo "$sinks" | jq -r ".[$next_sink_index]")
next_sink_name=$(echo "$next_sink" | jq -r '.name')
next_sink_description=$(echo "$next_sink" | jq -r '.description')

# Fallback for Bluetooth devices
if [[ $next_sink_description == "null" || -z $next_sink_description ]]; then
  device_id=$(echo "$next_sink" | jq -r '.properties."device.id"')
  if [[ $device_id != "null" && -n $device_id ]]; then
    next_sink_description=$(wpctl status | grep -E "^\s*│?\s+${device_id}\." | sed -E 's/^.*[0-9]+\.\s+//' | sed -E 's/\s+\[.*$//')
  fi
fi

[[ -z $next_sink_description ]] && next_sink_description="$next_sink_name"

# With a single sink the cycle lands back on the one already selected. That set
# no default and still reported "Switched to", so the only machine where this
# key does nothing was also the only one where it always claimed success.
if [[ $next_sink_name == "$current_sink_name" ]]; then
  notify-send "Audio Output" "Only one audio output: $next_sink_description"
  exit 0
fi

pactl set-default-sink "$next_sink_name"
notify-send "Audio Output" "Switched to: $next_sink_description"
