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
  # -replace: rofi runs one instance at a time, so without it this menu did
  # not open while another was up. It now closes that one and takes its place.
  rofi -replace -dmenu -i -format i -p "󰍹" -theme "$THEME") || exit 0

# Empty when the menu was dismissed, which is not a failure.
[[ -n $choice ]] || exit 0

# rofi has been asked for an index, so anything else means it answered in a
# shape this script did not ask for, and dispatching on it would run whichever
# entry the number happened to land on.
if [[ ! $choice =~ ^[0-9]+$ ]] || ((choice >= ${#modes[@]})); then
  notify-send -u critical "Screenshot" "The menu returned something unexpected, so nothing was captured"
  exit 1
fi

# Waits until the menu is off the screen, not for a guessed moment.
#
# hyprshot freezes the screen before the selection, so anything still drawn then
# is in the shot. This used to sleep a fixed 0.2 seconds, and rofi takes longer
# than that to leave. Its layer closes with the slower of two Hyprland
# animations, both inherited from hyprsimple's own config: layersOut takes
# global, speed 8, and fadeLayersOut takes fade, speed 5, where speed is tenths
# of a second. So the menu was still fading out when the screen froze.
#
# Two steps. The rofi layer is polled until the compositor no longer lists it,
# then the close animation is waited out, read from hyprctl rather than written
# here so a theme or a user who changes the speeds is still right.
wait_for_menu_to_close() {
  # An explicit value wins, for anyone who wants a fixed pause, and for the
  # suite, which runs with no compositor.
  if [[ -n ${HYPRSIMPLE_SCREENSHOT_MENU_SETTLE:-} ]]; then
    sleep "$HYPRSIMPLE_SCREENSHOT_MENU_SETTLE"
    return
  fi

  # Not on Hyprland, or no jq, so nothing can be asked. A second covers the
  # slowest close hyprsimple ships.
  if ! command -v hyprctl >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
    sleep 1
    return
  fi

  # Capped at twenty polls, a second, so a layer that never goes cannot stop the
  # screenshot from being taken at all.
  local polls=0
  while ((polls < 20)) && hyprctl layers -j 2>/dev/null |
    jq -e '[.[].levels[][] | select(.namespace == "rofi")] | length > 0' >/dev/null 2>&1; do
    sleep 0.05
    polls=$((polls + 1))
  done

  # A leaf that is not overridden inherits from its parent, so each chain is
  # walked to the first node that sets a value. A disabled animation takes no
  # time. Capped at two seconds.
  local close
  close=$(hyprctl animations -j 2>/dev/null | jq -r '
    def effective($a; $chain):
      [$chain[] as $n | $a[$n] | select(. != null and .overridden == true)]
      | (first // $a.global);
    (.[0] | map({key: .name, value: .}) | from_entries) as $a
    | [effective($a; ["layersOut", "layers", "global"]),
       effective($a; ["fadeLayersOut", "fadeLayers", "fade", "global"])]
    | map(if . == null then 0 elif .enabled then .speed / 10 else 0 end)
    | [max, 2] | min' 2>/dev/null)
  [[ $close =~ ^[0-9]+(\.[0-9]+)?$ ]] || close=1
  sleep "$close"
}

wait_for_menu_to_close

exec "$SHOOTER" "${modes[$choice]}"
