#!/bin/bash

# Move audio to a Bluetooth output when one connects.
#
# WirePlumber chooses the default sink by priority, and a bluetooth sink
# outranks the built-in one on its own: measured on this project's own hardware,
# priority.session 1010 against 1009. So on a fresh install a headset takes over
# by itself and there is nothing to do.
#
# What stops that is an explicitly chosen default. find-selected-default-node.lua
# in WirePlumber 0.5 does
#
#   if current_configured_node == name then
#     priority = 30000 + priority
#
# to whatever default.configured.audio.sink names, so the chosen sink scores
# 31009 and no bluetooth device can ever outrank it. audio-switch.sh, on
# SUPER + F10, writes that key through `pactl set-default-sink`. Pressing the
# audio switch once therefore turned bluetooth auto-switching off for good, on
# every machine, and nothing said so. Reported as a headset that connects and
# then gets no sound.
#
# Only on appearance. A device already connected when this starts is left where
# it is, and a switch away from it by hand is not undone, because either would
# be this script arguing with the person using it.

set -uo pipefail

# Overridable so the suite can point them at stubs without a PATH that could
# reach the real ones.
PACTL="${HYPRSIMPLE_PACTL:-pactl}"

bluez_sinks() {
  # Names only, one per line. `list short` rather than the json form: this runs
  # on every sink event, and it needs no jq.
  "$PACTL" list short sinks 2>/dev/null | cut -f2 | grep '^bluez_output\.' || true
}

describe() {
  local name="$1" description
  description=$("$PACTL" list sinks 2>/dev/null |
    awk -v n="$name" '$1 == "Name:" && $2 == n { found = 1 }
                      found && $1 == "Description:" { $1 = ""; sub(/^ /, ""); print; exit }')
  printf '%s' "${description:-$name}"
}

switch_to() {
  local name="$1"
  # Checked, not assumed. The sink list this came from is a moment old, and a
  # headset that drops in between leaves the sound where it was while a
  # notification claims it moved. audio-switch.sh had that exact bug once.
  if "$PACTL" set-default-sink "$name" 2>/dev/null; then
    notify-send "Audio Output" "Switched to: $(describe "$name")" -t 2000
  fi
}

# What was already connected when this started, so the first event does not
# read every existing device as new.
known=" $(bluez_sinks | tr '\n' ' ')"

# `pactl subscribe` prints a line per event and never exits on its own. The
# unit restarts it, which is what covers pipewire-pulse itself restarting.
"$PACTL" subscribe 2>/dev/null | while read -r event; do
  case "$event" in
  *"on sink"*) ;;
  *) continue ;;
  esac

  now=" $(bluez_sinks | tr '\n' ' ')"
  for sink in $now; do
    case "$known" in
    *" $sink "*) continue ;;
    esac
    switch_to "$sink"
  done
  known="$now"
done
