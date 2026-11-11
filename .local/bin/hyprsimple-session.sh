#!/bin/bash
# Add or remove a "Hyprsimple" entry on the login screen.
#
#   hyprsimple-session.sh          add the entry
#   hyprsimple-session.sh remove   remove it
#
# The entry starts the same ~/.config/hypr/hyprland.lua the stock Hyprland
# entry starts. It changes the name on the login screen and puts Hyprsimple
# into XDG_CURRENT_DESKTOP, nothing else. The FAQ says what stays shared with
# another Hyprland setup on the same user:
# https://rizukirr.github.io/hyprsimple-web/docs/faq#can-i-run-hyprsimple-beside-another-hyprland-setup
#
# HYPRSIMPLE_SESSION_DIR overrides the directory, for the test suite.
set -euo pipefail

DIR="${HYPRSIMPLE_SESSION_DIR:-/usr/local/share/wayland-sessions}"
FILE="$DIR/hyprsimple.desktop"

# hyprland.desktop as the compositor argument, the way the stock
# hyprland-uwsm.desktop passes it, so Hyprland's own Exec is reused rather than
# copied here. Hyprland stays first in -D so the portal still matches on it.
ENTRY='[Desktop Entry]
Name=Hyprsimple
Comment=Hyprland configured by hyprsimple
Exec=uwsm start -e -D Hyprland:Hyprsimple -N Hyprsimple hyprland.desktop
TryExec=uwsm
DesktopNames=Hyprland
Type=Application'

usage() {
  cat <<USAGE
Usage: hyprsimple-session.sh [remove]

  (no argument)  Add a "Hyprsimple" entry to the login screen, at
                 $FILE
                 It starts the same config as the stock Hyprland entry.
  remove         Remove that entry.
USAGE
}

# Directly when this user may write there, through sudo otherwise. The
# directory may not exist yet, so the nearest thing that does is what is
# probed. Under HYPRSIMPLE_SESSION_DIR in a test the directory is the user's
# own and sudo is never reached.
run() {
  local probe="$DIR"
  [[ -e $probe ]] || probe="$(dirname "$probe")"
  if [[ -w $probe ]]; then "$@"; else sudo "$@"; fi
}

install_entry() {
  if [[ -f $FILE ]] && [[ "$(cat "$FILE")" == "$ENTRY" ]]; then
    echo "The Hyprsimple login entry is already at $FILE."
    exit 0
  fi
  run mkdir -p "$DIR"
  printf '%s\n' "$ENTRY" | run tee "$FILE" >/dev/null
  if [[ "$(cat "$FILE" 2>/dev/null)" != "$ENTRY" ]]; then
    echo "Could not write $FILE." >&2
    exit 1
  fi
  echo "Added the Hyprsimple login entry at $FILE. It appears at the next login."
}

remove_entry() {
  if [[ ! -e $FILE ]]; then
    echo "There is no Hyprsimple login entry at $FILE, nothing to remove."
    exit 0
  fi
  run rm -f "$FILE"
  if [[ -e $FILE ]]; then
    echo "Could not remove $FILE." >&2
    exit 1
  fi
  echo "Removed the Hyprsimple login entry at $FILE."
}

case "${1-}" in
"") install_entry ;;
remove) remove_entry ;;
-h | --help) usage ;;
*)
  usage >&2
  exit 1
  ;;
esac
