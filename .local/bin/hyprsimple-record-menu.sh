#!/bin/bash

# The recording menu, opened by SUPER + R.
#
# It is a panel of the bar: region, window or whole screen, with the
# microphone, the system audio or no sound. While a recording runs the panel
# offers only to stop it. The panel runs screen-record.sh with what was chosen,
# and this script only opens it.

RECORDER="$HOME/.local/bin/screen-record.sh"

# Said here rather than after a choice has been made in the panel, where the
# recording would simply not start.
if [[ ! -x $RECORDER ]]; then
  notify-send -u critical "Recording" "screen-record.sh is missing. Run hyprsimple-update."
  exit 1
fi

BAR="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/default/quickshell"

exec qs -p "$BAR" ipc call bar toggle record
