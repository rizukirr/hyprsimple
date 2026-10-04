#!/bin/bash

# The clipboard history, opened by SUPER + V.
#
# It is a panel of the bar now, and this script only opens it. The script stays
# because the binding that calls it lives in a file the user owns,
# ~/.config/hypr/bindings/applications.lua, which an update never rewrites.
#
# The panel lists cliphist's history, and copies an entry only when one was
# picked and it decoded into something. That rule came from the menu this
# replaced, which piped its answer through cliphist decode into wl-copy and so
# wiped the clipboard when it was dismissed: the menu printed nothing, cliphist
# decode printed nothing, and wl-copy copied that nothing.

command -v cliphist >/dev/null 2>&1 || {
  notify-send -u critical "Clipboard" "cliphist is not installed"
  exit 1
}

BAR="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/default/quickshell"

exec qs -p "$BAR" ipc call bar toggle clipboard
