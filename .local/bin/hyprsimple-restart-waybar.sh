#!/bin/bash

# Restart waybar. setsid plus the redirect detach it from the caller, so a
# piped or non-interactive caller returns instead of waiting on the daemon's
# inherited stdout.
#
# --if-running reloads a bar that is already up and does nothing otherwise.
# Without it, waybar is started whether or not one was running, which is what
# install.sh needs.

if [[ $1 == --if-running ]] && ! pgrep -x waybar >/dev/null; then
  exit 0
fi

pkill -x waybar
setsid uwsm app -- waybar >/dev/null 2>&1 &
