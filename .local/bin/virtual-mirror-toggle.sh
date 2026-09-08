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

PRIMARY=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused == true) | .name')

if pgrep -x wl-mirror >/dev/null; then
  pkill -x wl-mirror
  notify-send "Virtual Mirror" "Stopped"
else
  # A name, before anything is told to mirror it.
  #
  # This went unchecked, so a compositor that answered without a focused
  # monitor gave an empty name, wl-mirror was run with "" and refused it, and
  # the notification read "Mirroring  - Select this window in screen sharing
  # apps" with a blank where the monitor should be.
  if [[ -z $PRIMARY ]]; then
    notify-send -u critical "Virtual Mirror" "Could not tell which monitor is focused"
    exit 1
  fi

  wl-mirror "$PRIMARY" &
  mirror_pid=$!

  # wl-mirror is backgrounded, so a refused output or a missing protocol ends it
  # at once and silently. Without this the notification told the user to go and
  # select a window that was never opened, which is worse than saying nothing:
  # the whole point of this key is that the window exists to be shared.
  #
  # screen-record.sh does the same for the same reason, and the wait is
  # overridable there too so a suite need not sit through it.
  sleep "${HYPRSIMPLE_MIRROR_START_WAIT:-0.4}"
  if ! kill -0 "$mirror_pid" 2>/dev/null; then
    notify-send -u critical "Virtual Mirror" "wl-mirror could not mirror $PRIMARY"
    exit 1
  fi

  notify-send "Virtual Mirror" "Mirroring $PRIMARY - Select this window in screen sharing apps"
fi
