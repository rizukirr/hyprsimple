#!/bin/bash

set -e

usage() {
  echo "Usage: $(basename "$0") <mode>" >&2
  echo "Modes: clipboard, window, region, monitor" >&2
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
  # A mode that is not one of the four used to fall past every branch and exit
  # 0, so a typo took no screenshot and reported success.
  usage
  ;;
esac
