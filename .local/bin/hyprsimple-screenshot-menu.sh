#!/bin/bash

# The screenshot menu, opened by Print.
#
# It is a panel of the bar: region, window or whole screen, saved to a file or
# copied to the clipboard. The panel runs screenshot.sh with the mode chosen,
# after it has left the screen, so the menu is never in the picture. This
# script only opens it.

SHOOTER="$HOME/.local/bin/screenshot.sh"

# Said here rather than after a choice has been made in the panel, where the
# capture would simply not happen.
if [[ ! -x $SHOOTER ]]; then
  notify-send -u critical "Screenshot" "screenshot.sh is missing. Run hyprsimple-update."
  exit 1
fi

BAR="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/default/quickshell"

# Through the helper, so a rofi menu that is open is closed first.
exec "$HOME/.local/bin/hyprsimple-menu-exclusive.sh" qs -p "$BAR" ipc call bar toggle screenshot
