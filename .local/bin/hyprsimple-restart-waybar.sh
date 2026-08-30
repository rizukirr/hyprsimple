#!/bin/bash

# Restart waybar. setsid plus the redirect detach it from the caller, so a
# piped or non-interactive caller returns instead of waiting on the daemon's
# inherited stdout.

pkill -x waybar
setsid uwsm app -- waybar >/dev/null 2>&1 &
