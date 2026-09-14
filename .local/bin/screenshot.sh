#!/bin/bash

set -e

usage() {
  echo "Usage: $(basename "$0") <mode>" >&2
  echo "Modes: region, window, monitor, region-clipboard, window-clipboard, clipboard" >&2
  exit 1
}

mode="${1:-}"
SHOTS="$HOME/Pictures/Screenshots"

case "$mode" in
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
