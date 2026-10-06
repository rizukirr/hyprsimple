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
# --toggle     hides a running bar or shows it again, and starts a stopped one.
#              Hiding does not stop it: the bar also shows the notifications,
#              which a stopped one would silently drop.
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
      exec qs -p "$BAR" ipc call bar toggleVisible
    fi
    ;;
esac

# The old bar is asked to quit, and signalled only if it does not.
#
# Quickshell does not take its child processes down when a signal ends it. The
# bar has one that never exits by itself, the dbus-monitor that watches
# hypridle, so every restart by pkill left one behind until logout. Asked to
# quit, it stops them first.
#
# It gets two seconds, since a signal sent while it is still quitting would
# cut that short and orphan them after all.
if bar_running; then
  qs kill -p "$BAR" >/dev/null 2>&1
  for _ in {1..20}; do
    bar_running || break
    sleep 0.1
  done
  bar_running && pkill -f -- "qs -p $BAR"
fi

setsid uwsm app -- qs -p "$BAR" >/dev/null 2>&1 &
