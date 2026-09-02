#!/bin/bash

set -e

mode="$1"

if [ -z "$mode" ]; then
  echo "Usage: $0 <mode>"
  echo "Modes: clipboard, window, region, monitor"
  exit 1
fi

if [ "$mode" == "clipboard" ]; then
    hyprshot -m output --clipboard-only
    notify-send "Screenshot" "Copied to clipboard"
    exit 0
fi

if [ "$mode" == "window" ]; then
    hyprshot -m window --freeze --output-folder $HOME/Pictures/Screenshots
    exit 0
fi

if [ "$mode" == "region" ]; then
    hyprshot -m region --freze --output-folder $HOME/Pictures/Screenshots
    exit 0
fi

if [ "$mode" == "monitor" ]; then
    hyprshot -m output --freeze --output-folder $HOME/Pictures/Screenshots
    exit 0
fi
