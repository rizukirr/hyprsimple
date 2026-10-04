#!/bin/bash

# The clipboard history, opened by SUPER + V.
#
# It is a panel of the bar now, and this script only opens it. The script stays
# because the binding that calls it lives in a file the user owns,
# ~/.config/hypr/bindings/applications.lua, which an update never rewrites.
#
# The panel lists cliphist's history, and copies an entry only when one was
# picked and it decoded into something. That rule came from the rofi version of
# this script, which was once
#
#   sh -c 'cliphist list | rofi --show dmenu | cliphist decode | wl-copy'
#
# and wiped the clipboard when the menu was dismissed: rofi printed nothing,
# cliphist decode printed nothing, and wl-copy copied that nothing.

command -v cliphist >/dev/null 2>&1 || {
  notify-send -u critical "Clipboard" "cliphist is not installed"
  exit 1
}

BAR="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/default/quickshell"

# Through the helper, so a rofi menu that is open is closed first.
exec "$HOME/.local/bin/hyprsimple-menu-exclusive.sh" qs -p "$BAR" ipc call bar toggle clipboard
