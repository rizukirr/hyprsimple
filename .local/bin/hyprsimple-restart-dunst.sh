#!/bin/bash

# Restart dunst. setsid plus the redirect detach it from the caller, so a piped
# or non-interactive caller returns instead of waiting on the daemon's
# inherited stdout.
#
# --if-running reloads a daemon that is already up and does nothing otherwise.

if [[ $1 == --if-running ]] && ! pgrep -x dunst >/dev/null; then
  exit 0
fi

pkill -x dunst
setsid uwsm app -- dunst >/dev/null 2>&1 &
