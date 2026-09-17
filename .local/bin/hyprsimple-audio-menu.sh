#!/bin/bash

# The audio menu, opened by SUPER + S.
#
# SUPER + F10 cycled speakers blindly and there was no way to choose a
# microphone at all. This lists every speaker and every microphone, marks the
# one in use of each, and switches whichever line is picked.
#
# Only devices are offered. A source or sink with no device.api is something
# built on top of a device rather than a device: hyprsimple's noise filter is
# one, and offering it as a microphone would ask the filter to listen to
# itself. The bluetooth microphone is a device even though WirePlumber builds
# it as a loopback, and it carries device.api bluez5, so it stays.
#
# Choosing a microphone keeps noise suppression. The filter is a WirePlumber
# smart filter that follows the default source, so setting the default is all
# this has to do.
#
# The selection is read back as an index, the same as the recording and
# screenshot menus, so a device description cannot change what runs.

THEME="$HOME/.config/rofi/audio/style.rasi"

fail() {
  notify-send -u critical "Audio" "$1"
  exit 1
}

command -v pactl >/dev/null 2>&1 || fail "pactl is not installed, so no device can be switched"
command -v jq >/dev/null 2>&1 || fail "jq is not installed, so the device list cannot be read"

sinks=$(pactl -f json list sinks 2>/dev/null) || fail "Could not read the speakers. Is pipewire-pulse running?"
sources=$(pactl -f json list sources 2>/dev/null) || fail "Could not read the microphones. Is pipewire-pulse running?"
default_sink=$(pactl get-default-sink 2>/dev/null)
default_source=$(pactl get-default-source 2>/dev/null)

labels=()
actions=()
names=()

# Tab separated, name then description. A description can hold spaces, and a
# node name never holds a tab.
devices() {
  jq -r '.[]
    | select(.properties["device.api"] != null)
    | select(.name | endswith(".monitor") | not)
    | [.name, (.description // .name)] | @tsv' <<<"$1" 2>/dev/null
}

while IFS=$'\t' read -r name description; do
  [[ -n $name ]] || continue
  mark=""
  [[ $name == "$default_sink" ]] && mark="  (in use)"
  labels+=("󰓃  Speaker  $description$mark")
  actions+=("set-default-sink")
  names+=("$name|$description|Speaker")
done < <(devices "$sinks")

while IFS=$'\t' read -r name description; do
  [[ -n $name ]] || continue
  mark=""
  [[ $name == "$default_source" ]] && mark="  (in use)"
  labels+=("󰍬  Mic      $description$mark")
  actions+=("set-default-source")
  names+=("$name|$description|Microphone")
done < <(devices "$sources")

((${#labels[@]} > 0)) || fail "No audio devices found"

choice=$(printf '%s\n' "${labels[@]}" |
  rofi -dmenu -i -format i -p "󰓃" -theme "$THEME") || exit 0

# Empty when the menu was dismissed, which is not a failure.
[[ -n $choice ]] || exit 0

# rofi has been asked for an index, so anything else means it answered in a
# shape this script did not ask for.
if [[ ! $choice =~ ^[0-9]+$ ]] || ((choice >= ${#actions[@]})); then
  fail "The menu returned something unexpected, so nothing was switched"
fi

IFS='|' read -r name description kind <<<"${names[$choice]}"

# Reported only if pactl made the change. The list is a moment old, and a
# bluetooth headset that disconnects in between would otherwise be announced
# as switched while the sound stays where it was.
if pactl "${actions[$choice]}" "$name" 2>/dev/null; then
  notify-send "Audio" "$kind: $description"
else
  fail "Could not switch to $description"
fi
