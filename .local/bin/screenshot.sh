#!/bin/bash

set -e

usage() {
  echo "Usage: $(basename "$0") <mode>" >&2
  echo "Modes: smart, region, window, monitor, region-clipboard, window-clipboard, clipboard" >&2
  exit 1
}

mode="${1:-}"
SHOTS="$HOME/Pictures/Screenshots"

# One gesture for every kind of screenshot, which is what Print does.
#
# The screen is frozen and slurp is shown with every monitor and every window
# on the active workspace as a box it can snap to. Dragging takes a region,
# and a click takes the window under the pointer, or the whole monitor when
# there is no window there. Escape takes nothing. The picture is saved and
# copied to the clipboard, both, so there is nothing to choose beforehand.
#
# The approach is Omarchy's, from its omarchy-capture-region.
smart() {
  local tool
  for tool in slurp grim jq hyprpicker wl-copy; do
    command -v "$tool" >/dev/null 2>&1 || {
      notify-send -u critical "Screenshot" "$tool is not installed"
      exit 1
    }
  done

  # The workspace on the focused monitor. Windows elsewhere are not on screen,
  # and a box for one would let a click capture whatever is drawn in its place.
  local workspace rects
  workspace=$(hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .activeWorkspace.id')

  # Monitors first, then windows. slurp snaps to the smallest box under the
  # pointer, so a window wins over the monitor it is on. A rotated monitor has
  # its width and height swapped, and both are divided by its scale, because
  # slurp works in the layout's coordinates. Windows stacked at the same place,
  # such as a group, are listed once.
  rects=$({
    hyprctl monitors -j | jq -r '.[]
      | (.width / .scale | floor) as $w | (.height / .scale | floor) as $h
      | if .transform == 1 or .transform == 3 then "\(.x),\(.y) \($h)x\($w)" else "\(.x),\(.y) \($w)x\($h)" end'
    hyprctl clients -j | jq -r --argjson ws "${workspace:-0}" \
      '[.[] | select(.workspace.id == $ws and .hidden != true) | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"] | unique[]'
  })

  # Frozen, so what is captured is what was on screen when Print was pressed,
  # whatever moves while the area is being picked.
  hyprpicker -r -z >/dev/null 2>&1 &
  local freeze=$!
  # shellcheck disable=SC2064  # expanded now on purpose: the pid is known here
  trap "kill $freeze 2>/dev/null" EXIT
  sleep "${HYPRSIMPLE_SCREENSHOT_FREEZE_WAIT:-0.1}"

  local selection
  selection=$(slurp <<<"$rects" 2>/dev/null) || selection=""
  # Escape, or a click outside every box. Nothing is captured and nothing is said.
  [[ -n $selection ]] || exit 0

  # A bare click that slurp reports as a tiny area of its own is snapped to the
  # smallest box it landed in, so it does not become a two pixel picture.
  if [[ $selection =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] &&
    ((BASH_REMATCH[3] * BASH_REMATCH[4] < 20)); then
    local x=${BASH_REMATCH[1]} y=${BASH_REMATCH[2]} rect best="" best_area=0 area
    while IFS= read -r rect; do
      [[ $rect =~ ^(-?[0-9]+),(-?[0-9]+)[[:space:]]([0-9]+)x([0-9]+)$ ]] || continue
      ((x >= BASH_REMATCH[1] && x < BASH_REMATCH[1] + BASH_REMATCH[3] &&
        y >= BASH_REMATCH[2] && y < BASH_REMATCH[2] + BASH_REMATCH[4])) || continue
      area=$((BASH_REMATCH[3] * BASH_REMATCH[4]))
      if [[ -z $best ]] || ((area < best_area)); then
        best=$rect
        best_area=$area
      fi
    done <<<"$rects"
    [[ -n $best ]] && selection=$best
  fi

  mkdir -p "$SHOTS"
  local file
  file="$SHOTS/$(date +%Y-%m-%d-%H%M%S)_screenshot.png"
  # Taken while the screen is still frozen. slurp's own overlay is gone by now:
  # it has exited, and a layer rule stops Hyprland fading its layer out.
  if ! grim -g "$selection" "$file"; then
    notify-send -u critical "Screenshot" "Could not capture the screen"
    exit 1
  fi
  wl-copy --type image/png <"$file"
  notify-send "Screenshot" "Saved to ${file/#$HOME/\~} and copied to the clipboard" -i "$file"
}

case "$mode" in
smart)
  smart
  ;;
clipboard)
  # --silent because hyprsimple sends its own message below. hyprshot notifies
  # unless told not to, so without this the one keypress produced two
  # notifications saying the same thing: its "Image copied to the clipboard"
  # and ours.
  hyprshot -m output --clipboard-only --silent
  notify-send "Screenshot" "Copied to clipboard"
  ;;
region-clipboard)
  # The menu offers every capture both ways. Only the whole screen could reach
  # the clipboard before, which is the one least often wanted there: a region is
  # what gets pasted into a chat.
  hyprshot -m region --freeze --clipboard-only --silent
  notify-send "Screenshot" "Region copied to clipboard"
  ;;
window-clipboard)
  hyprshot -m window --freeze --clipboard-only --silent
  notify-send "Screenshot" "Window copied to clipboard"
  ;;
window)
  # The three saving modes have no notify of their own: hyprshot's names the
  # file it wrote, which is more useful than anything repeated here.
  hyprshot -m window --freeze --output-folder "$SHOTS"
  ;;
region)
  hyprshot -m region --freeze --output-folder "$SHOTS"
  ;;
monitor)
  hyprshot -m output --freeze --output-folder "$SHOTS"
  ;;
*)
  # A mode that is not one of these used to fall past every branch and exit
  # 0, so a typo took no screenshot and reported success.
  usage
  ;;
esac
