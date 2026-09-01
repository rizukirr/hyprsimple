#!/bin/bash

# Emit one row per theme for hyprsimple-image-picker.sh:
#
#   theme directory name <TAB> display name and colour swatches <TAB> wallpaper
#
# The key is the directory name, so the picker returns something usable directly
# and no display string is transformed back into an identifier.

THEMES_DIR="${THEMES_DIR:-$HOME/.config/hypr/themes}"

# background, foreground, accent, color1. Not the ANSI spread: accent and
# color4 are the same value in 12 of the 16 shipped themes, so a swatch was
# wasted on most of them. These four are also what the interface itself uses,
# which the wallpaper does not tell you.
swatches_for() {
  local colors="$1" key hex out=""
  [[ -f $colors ]] || return
  for key in background foreground accent color1; do
    hex=$(sed -n "s/^${key}[[:space:]]*=[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p" "$colors" | head -n 1)
    [[ -n $hex ]] && out+="<span background='$hex'>  </span>"
  done
  printf '%s' "$out"
}

for dir in "$THEMES_DIR"/*/; do
  name=$(basename "$dir")
  # templates holds the render inputs and templates.user holds a user's
  # overrides of them. Neither is a theme.
  [[ $name == templates || $name == templates.user ]] && continue

  wallpaper=$(find "$dir/backgrounds" -maxdepth 1 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' \) 2>/dev/null | sort | head -n 1)

  printf '%s\t%s  %s\t%s\n' "$name" "$(swatches_for "$dir/colors.toml")" "${name//-/ }" "$wallpaper"
done
