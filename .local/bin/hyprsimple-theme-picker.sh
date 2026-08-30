#!/bin/bash

# Emit a rofi dmenu feed: one tile per theme, the theme's wallpaper as the icon
# and its name plus colour swatches as pango markup.
#
# Wallpapers are 2560px wide, so decoding sixteen of them on every open costs
# about 1.8 seconds. Thumbnails cut that to about 0.16s. The -nt test is the
# whole invalidation strategy: a changed wallpaper is newer than its thumbnail,
# and a new theme has no thumbnail at all.
#
# This is bound to a key, so nothing here may fail the whole picker. A theme
# with no wallpaper is listed without one, and with no ImageMagick the
# full-size image is used instead of a thumbnail.

THEMES_DIR="${THEMES_DIR:-$HOME/.config/hypr/themes}"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hyprsimple/theme-previews"
THUMB_SIZE=220

mkdir -p "$CACHE_DIR" 2>/dev/null

# background, foreground, accent, color1. Not the ANSI spread: accent and
# color4 are the same value in 12 of the 16 shipped themes, so a swatch was
# wasted on most of them. These four are also what the interface itself uses,
# which the wallpaper does not tell you.
swatches_for() {
  local colors="$1" key hex out=""
  [[ -f $colors ]] || return
  for key in background foreground accent color1; do
    hex=$(sed -n "s/^${key}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$colors" | head -n 1)
    [[ -n $hex ]] && out+="<span background='$hex'>    </span>"
  done
  printf '%s' "$out"
}

thumbnail_for() {
  local name="$1" src="$2" thumb="$CACHE_DIR/$name.jpg"

  if [[ $thumb -nt $src ]]; then
    printf '%s' "$thumb"
    return
  fi

  if command -v magick >/dev/null 2>&1 &&
    magick "$src" -resize "${THUMB_SIZE}x${THUMB_SIZE}^" -gravity center \
      -extent "${THUMB_SIZE}x${THUMB_SIZE}" "$thumb" 2>/dev/null; then
    printf '%s' "$thumb"
  else
    # No ImageMagick, or it failed. rofi scales the original itself, slower but
    # correct, which beats a picker that shows nothing.
    printf '%s' "$src"
  fi
}

for dir in "$THEMES_DIR"/*/; do
  name=$(basename "$dir")
  [[ $name == templates ]] && continue

  wallpaper=$(find "$dir/backgrounds" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | sort | head -n 1)

  label="${name//-/ }  $(swatches_for "$dir/colors.toml")"

  if [[ -n $wallpaper ]]; then
    printf '%s\0icon\x1f%s\n' "$label" "$(thumbnail_for "$name" "$wallpaper")"
  else
    # Listed without an icon rather than dropped. A theme is still selectable
    # when its wallpaper is missing.
    printf '%s\n' "$label"
  fi
done
