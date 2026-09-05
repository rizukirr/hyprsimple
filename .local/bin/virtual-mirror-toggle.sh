#!/bin/bash

# Toggle virtual mirror using wl-mirror
# Auto-detects primary monitor

# wl-mirror is an AUR package, so an install that skipped the AUR list has the
# keybind without the program. Without this the notification below announced a
# mirror that never started.
if ! command -v wl-mirror >/dev/null; then
  notify-send "Virtual Mirror" "wl-mirror is not installed"
  exit 1
fi

PRIMARY=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name')

if pgrep -x wl-mirror >/dev/null; then
  pkill -x wl-mirror
  notify-send "Virtual Mirror" "Stopped"
else
  wl-mirror "$PRIMARY" &
  notify-send "Virtual Mirror" "Mirroring $PRIMARY - Select this window in screen sharing apps"
fi
