#!/bin/bash

# The clipboard history menu, opened by SUPER + V.
#
# This was
#
#   sh -c 'cliphist list | rofi --show dmenu | cliphist decode | wl-copy'
#
# and dismissing the menu wiped the clipboard. rofi printed nothing, cliphist
# decode printed nothing, and wl-copy copied that nothing. wl-clipboard's own
# manual names "wl-copy < /dev/null" as the way to put zero-sized data on the
# clipboard, so pressing Escape replaced whatever had been copied with an empty
# clipboard.
#
# Now nothing reaches wl-copy unless an entry was picked and decoded into
# something. The decoded entry goes through a file rather than a variable,
# because an image in the history is binary and a shell variable cannot hold a
# NUL byte.

command -v cliphist >/dev/null 2>&1 || {
  notify-send -u critical "Clipboard" "cliphist is not installed"
  exit 1
}

# -replace, so opening this with another menu up closes that one rather than
# doing nothing.
choice=$(cliphist list | rofi -replace -dmenu) || exit 0
[[ -n $choice ]] || exit 0

decoded=$(mktemp) || exit 1
trap 'rm -f "$decoded"' EXIT

if printf '%s\n' "$choice" | cliphist decode >"$decoded" && [[ -s $decoded ]]; then
  wl-copy <"$decoded"
fi
