#!/bin/bash

# Start, restart or toggle the bar, which is the Quickshell config hyprsimple
# ships in default/quickshell. setsid plus the redirect detach it from the
# caller, so a piped or non-interactive caller returns instead of waiting on
# the bar's inherited stdout.
#
# With no argument the bar is started whether or not one was running, which is
# what login and install.sh need.
#
# --if-running restarts a bar that is already up and does nothing otherwise.
# --toggle     stops a running bar and starts a stopped one.
#
# The bar is matched by its config path, not by process name. Quickshell runs
# any number of configs under the one name "qs", and killing by name would take
# down a shell the user runs alongside this one.

BAR="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/default/quickshell"

bar_running() {
  pgrep -f -- "qs -p $BAR" >/dev/null
}

case "${1:-}" in
  --if-running)
    bar_running || exit 0
    ;;
  --toggle)
    if bar_running; then
      pkill -f -- "qs -p $BAR"
      exit 0
    fi
    ;;
esac

pkill -f -- "qs -p $BAR"
setsid uwsm app -- qs -p "$BAR" >/dev/null 2>&1 &
