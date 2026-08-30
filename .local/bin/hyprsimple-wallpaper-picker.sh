#!/bin/bash

# Emit one row per wallpaper in the current theme for hyprsimple-image-picker.sh:
#
#   image path <TAB> display name <TAB> image path
#
# The key and the image are the same thing here, so the picker returns a path
# the caller can apply directly.
#
# The theme is derived from ~/.cache/current_wallpaper_path, which is the only
# record of which theme is applied. wallpaper-switcher.sh derives it the same
# way at its line 12.

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}"
CURRENT=$(cat "$CACHE_DIR/current_wallpaper_path" 2>/dev/null)
BG_DIR=$(dirname "$CURRENT" 2>/dev/null)

[[ -d $BG_DIR ]] || exit 0

find "$BG_DIR" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null |
  sort |
  while read -r image; do
    base=$(basename "$image")
    # Strip the extension, then a leading sort prefix like "0-", then turn the
    # remaining hyphens into spaces: "0-morning-breeze.jpg" reads "morning breeze".
    label=${base%.*}
    label=${label#[0-9]-}
    printf '%s\t%s\t%s\n' "$image" "${label//-/ }" "$image"
  done
