#!/bin/bash

# The screenshot menu, opened by Print.
#
# There were four keybinds: Print, SUPER + Print, SUPER + ALT + Print and
# SUPER + CTRL + Print. Three of those are chords nobody remembers, and a
# region could only be saved, never copied. This is one key, and what to capture
# and where it goes are chosen from a list.
#
# The selection is read back as an index rather than by matching the label, the
# same as the recording menu. rofi returns the line it displayed, so matching on
# text ties the dispatch to the wording and to the icons in it. -format i
# returns the position in the list this script supplied, which cannot drift.
#
# The icons are written by codepoint in the repository and checked by the
# suite. Three glyphs in the recording menu were lost on the way into that file
# once, and the only sign was a gap in the list.

SHOOTER="$HOME/.local/bin/screenshot.sh"
THEME="$HOME/.config/rofi/screenshot/style.rasi"

if [[ ! -x $SHOOTER ]]; then
  notify-send -u critical "Screenshot" "screenshot.sh is missing. Run hyprsimple-update."
  exit 1
fi

labels=(
  "󰒉  Region, save to file"
  "󰒉  Region, copy to clipboard"
  "󰖯  Window, save to file"
  "󰖯  Window, copy to clipboard"
  "󰍹  Whole screen, save to file"
  "󰍹  Whole screen, copy to clipboard"
)
modes=(
  region
  region-clipboard
  window
  window-clipboard
  monitor
  clipboard
)

choice=$(printf '%s\n' "${labels[@]}" |
  rofi -dmenu -i -format i -p "󰍹" -theme "$THEME") || exit 0

# Empty when the menu was dismissed, which is not a failure.
[[ -n $choice ]] || exit 0

# rofi has been asked for an index, so anything else means it answered in a
# shape this script did not ask for, and dispatching on it would run whichever
# entry the number happened to land on.
if [[ ! $choice =~ ^[0-9]+$ ]] || ((choice >= ${#modes[@]})); then
  notify-send -u critical "Screenshot" "The menu returned something unexpected, so nothing was captured"
  exit 1
fi

# rofi is still closing when this runs, and a frozen capture taken in that
# moment can include the menu itself. hyprshot freezes the screen before the
# selection, so the pause goes before it rather than after.
sleep "${HYPRSIMPLE_SCREENSHOT_MENU_SETTLE:-0.2}"

exec "$SHOOTER" "${modes[$choice]}"
