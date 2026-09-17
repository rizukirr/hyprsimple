#!/bin/bash

# Close a rofi menu that is already open, then run the command given.
#
#   hyprsimple-menu-exclusive.sh ~/.config/rofi/launcher/launcher.sh
#
# rofi runs one instance at a time through its pid file, so a menu opened while
# another was up simply did not appear: opening the screenshot menu with the
# sound menu showing did nothing at all. hyprsimple's own menus pass rofi's
# -replace, which closes the open one and takes its place. The app launcher and
# power menu scripts are yours, so -replace cannot be added to them, and they
# are started through this instead, which does the same from outside.

PIDFILE="${HYPRSIMPLE_ROFI_PIDFILE:-${XDG_RUNTIME_DIR:-/run/user/$UID}/rofi.pid}"
# Overridable so the suite can point it at processes of its own.
PROC="${HYPRSIMPLE_PROC_DIR:-/proc}"

close_open_menu() {
  local pid waited=0
  [[ -r $PIDFILE ]] || return 0
  read -r pid <"$PIDFILE" 2>/dev/null
  [[ $pid =~ ^[0-9]+$ ]] || return 0

  # The pid file outlives rofi, and a pid is reused once its process is gone.
  # Only a process that is actually rofi is closed, so a stale file can never
  # take down whatever happens to hold that number now.
  [[ $(cat "$PROC/$pid/comm" 2>/dev/null) == rofi ]] || return 0

  kill "$pid" 2>/dev/null || return 0

  # Waited for, so the new menu does not start while the old one still holds
  # the pid file and refuses it. Capped at a second.
  while [[ -e $PROC/$pid ]] && ((waited < 20)); do
    sleep 0.05
    waited=$((waited + 1))
  done
}

close_open_menu

(($# > 0)) || exit 0
exec "$@"
