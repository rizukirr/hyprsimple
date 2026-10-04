#!/bin/bash

# Swap the image in each row of a picker feed for a small cached thumbnail.
#
# Reads tab-separated rows on stdin, "key<TAB>label<TAB>image", the feed
# hyprsimple-theme-picker.sh and hyprsimple-wallpaper-picker.sh print, and
# writes the same rows with the image replaced by a thumbnail of it. The bar's
# theme and wallpaper pickers show those.
#
# Thumbnails are there for two reasons. A wallpaper is several megabytes and a
# picker shows dozens, and the shipped wallpapers are webp, which Qt cannot
# read without a plugin hyprsimple does not install. A thumbnail is a small
# jpeg, which it always can.
#
# Each row is written as soon as its thumbnail exists, so the picker fills in
# as they are made rather than waiting for the last one. A thumbnail is made
# once and reused until its image changes.

if command -v magick >/dev/null 2>&1; then
  im() { magick "$@"; }
elif command -v convert >/dev/null 2>&1; then
  im() { convert "$@"; }
else
  im() { return 1; }
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hyprsimple/picker-thumbnails"
# The size the picker's cards are drawn at, doubled so they stay sharp on a
# scaled screen.
THUMB_SIZE=560x316

mkdir -p "$CACHE_DIR" 2>/dev/null

# Prints the thumbnail for an image, making it first when it is missing or
# older than the image. Falls back to the image itself when it cannot be made.
thumbnail_for() {
  local src="$1" hash thumb
  # Keyed on the resolved path, so a symlinked wallpaper and its target share
  # one thumbnail.
  hash=$(printf '%s' "$(readlink -f "$src" 2>/dev/null || printf '%s' "$src")" | md5sum | cut -d' ' -f1)
  thumb="$CACHE_DIR/$hash.jpg"
  if [[ $thumb -nt $src ]]; then
    printf '%s' "$thumb"
    return
  fi
  # Written beside the target and renamed, so a picker reading the folder never
  # sees half a file.
  if im "$src" -resize "${THUMB_SIZE}^" -gravity center -extent "$THUMB_SIZE" \
    -quality 85 "$thumb.tmp.jpg" 2>/dev/null && mv -f "$thumb.tmp.jpg" "$thumb"; then
    printf '%s' "$thumb"
  else
    rm -f "$thumb.tmp.jpg"
    printf '%s' "$src"
  fi
}

while IFS=$'\t' read -r key label image; do
  [[ -n $key ]] || continue
  if [[ -n $image && -f $image ]]; then
    printf '%s\t%s\t%s\n' "$key" "$label" "$(thumbnail_for "$image")"
  else
    printf '%s\t%s\t\n' "$key" "$label"
  fi
done
