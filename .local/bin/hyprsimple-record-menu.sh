#!/bin/bash

# The recording menu, opened by SUPER + R.
#
# There were six keybinds, one per combination of scope and audio source, and
# five of them were chords nobody remembers. This is the one key, and the
# combination is chosen from a list instead.
#
# The selection is read back as an index rather than by matching the label.
# rofi returns the line it displayed, so matching on text ties the dispatch to
# the wording and to the glyphs in it: renaming an entry, or a font that
# renders one differently, would silently stop it running. -format i returns
# the position in the list this script supplied, which cannot drift from it.

RECORDER="$HOME/.local/bin/screen-record.sh"
THEME="$HOME/.config/rofi/record/style.rasi"

if [[ ! -x $RECORDER ]]; then
  notify-send -u critical "Recording" "screen-record.sh is missing. Run hyprsimple-update."
  exit 1
fi

# Stopping is offered on its own when something is already recording. Showing
# the nine start options then would be offering to start a second recorder while
# the first holds the screen.
#
# The same test screen-record.sh uses, so the menu and the recorder cannot
# disagree about whether a recording is running.
if pgrep -x wl-screenrec >/dev/null || pgrep -x wf-recorder >/dev/null; then
  labels=("󰓛  Stop recording")
  args=("stop")
  prompt="󰻂"
else
  labels=(
    "󰗆  Region, microphone"
    "󰗆  Region, system audio"
    "󰗆  Region, no audio"
    "󰖯  Window, microphone"
    "󰖯  Window, system audio"
    "󰖯  Window, no audio"
    "󰍹  Whole screen, microphone"
    "󰍹  Whole screen, system audio"
    "󰍹  Whole screen, no audio"
  )
  args=(
    "region mic"
    "region internal"
    "region none"
    "window mic"
    "window internal"
    "window none"
    "output mic"
    "output internal"
    "output none"
  )
  prompt="󰑊"
fi

choice=$(printf '%s\n' "${labels[@]}" |
  # -replace: rofi runs one instance at a time, so without it this menu did
  # not open while another was up. It now closes that one and takes its place.
  rofi -replace -dmenu -i -format i -p "$prompt" -theme "$THEME") || exit 0

# Empty when the menu was dismissed, which is not a failure.
[[ -n $choice ]] || exit 0

# rofi has been asked for an index, so anything else means it answered in a
# shape this script did not ask for, and dispatching on it would run whichever
# entry the number happened to land on.
if [[ ! $choice =~ ^[0-9]+$ ]] || (( choice >= ${#args[@]} )); then
  notify-send -u critical "Recording" "The menu returned something unexpected, so nothing was started"
  exit 1
fi

# Unquoted on purpose: each entry is a scope and an audio mode, two arguments.
# shellcheck disable=SC2086
exec "$RECORDER" ${args[$choice]}
