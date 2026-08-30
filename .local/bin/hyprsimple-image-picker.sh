#!/bin/bash

# Render a list of images as a rofi grid and print the key of the one chosen.
#
# Reads tab separated rows on stdin:
#
#   key <TAB> label <TAB> image path
#
# The key is what gets printed. rofi runs with -format i, which returns the
# index of the selection, so the key is looked up rather than parsed back out of
# the label. Nothing transforms a display string into an identifier: doing that
# is what broke theme selection when the label gained leading colour swatches.
#
# This is bound to a key, so nothing here may fail the whole picker.

# ImageMagick 7 exposes `magick`. ImageMagick 6, which Ubuntu still ships,
# exposes `convert`. Support both, and degrade to full size images when neither
# is present.
if command -v magick >/dev/null 2>&1; then
  im() { magick "$@"; }
elif command -v convert >/dev/null 2>&1; then
  im() { convert "$@"; }
else
  im() { return 1; }
fi

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/hyprsimple/image-previews"
RASI="${HYPRSIMPLE_PICKER_RASI:-$HOME/.config/rofi/theme-picker/style.rasi}"
THUMB_SIZE=370
prompt="Select"
columns=3
selected_key=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prompt) prompt="$2"; shift 2 ;;
    --columns) columns="$2"; shift 2 ;;
    --selected) selected_key="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$CACHE_DIR" 2>/dev/null

# Keyed by the source path rather than a caller-supplied name, so two producers
# naming the same image share one entry and cannot collide.
thumbnail_for() {
  local src="$1" hash thumb
  hash=$(printf '%s' "$src" | md5sum | cut -d' ' -f1)
  thumb="$CACHE_DIR/$hash.jpg"

  if [[ $thumb -nt $src ]]; then
    printf '%s' "$thumb"
    return
  fi

  # rofi's icon box is square and takes no separate width and height, so a 16:9
  # image would leave a dead band that strands the caption. Fill the box with a
  # blurred zoomed copy and composite the whole undistorted image on top.
  if im "$src" -resize "${THUMB_SIZE}x${THUMB_SIZE}^" -gravity center \
    -extent "${THUMB_SIZE}x${THUMB_SIZE}" -blur 0x18 \
    \( "$src" -resize "${THUMB_SIZE}x" \) -gravity center -composite \
    "$thumb" 2>/dev/null; then
    printf '%s' "$thumb"
  else
    # No ImageMagick, or it failed. rofi scales the original itself, slower but
    # correct, which beats a picker that shows nothing.
    printf '%s' "$src"
  fi
}

# The feed goes to a file, not a variable. rofi's icon protocol needs a literal
# NUL between the label and the path, and bash cannot hold a NUL in a variable
# at all: command substitution silently drops it and every icon disappears.
keys=()
feed_file=$(mktemp) || exit 1
trap 'rm -f "$feed_file"' EXIT
row=0
selected_row=""

while IFS=$'\t' read -r key label image; do
  [[ -n $key ]] || continue
  keys+=("$key")
  [[ $key == "$selected_key" ]] && selected_row=$row

  if [[ -n $image && -f $image ]]; then
    printf '%s\0icon\x1f%s\n' "$label" "$(thumbnail_for "$image")" >>"$feed_file"
  else
    # Listed without an icon rather than dropped. A row whose image is missing
    # is still selectable.
    printf '%s\n' "$label" >>"$feed_file"
  fi
  row=$((row + 1))
done

((${#keys[@]})) || exit 0

args=(-dmenu -show-icons -markup-rows -format i -p "$prompt" -theme "$RASI"
      -theme-str "listview { columns: $columns; }")
[[ -n $selected_row ]] && args+=(-selected-row "$selected_row")

index=$(rofi "${args[@]}" <"$feed_file")
[[ -n $index ]] || exit 0
printf '%s\n' "${keys[$index]}"
