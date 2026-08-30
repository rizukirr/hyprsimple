#!/bin/bash

source "$HOME/.local/bin/hypr-helpers.sh"

# Switch wallpaper within the current theme
# Usage: wallpaper-switcher.sh [next|pick]
#   next - cycle to next wallpaper
#   pick - choose via rofi (default)

CACHE_DIR="$HOME/.cache"
# Track the actual wallpaper source path in a state file
CURRENT=$(cat "$CACHE_DIR/current_wallpaper_path" 2>/dev/null || readlink -f "$CACHE_DIR/current_wallpaper" 2>/dev/null)
THEME_DIR=$(dirname "$(dirname "$CURRENT")" 2>/dev/null)
BG_DIR="$THEME_DIR/backgrounds"

if [[ ! -d $BG_DIR ]]; then
  notify-send "Wallpaper" "No backgrounds folder found for current theme"
  exit 1
fi

# Get all wallpapers sorted
mapfile -t WALLPAPERS < <(find "$BG_DIR" -type f \( -name "*.png" -o -name "*.jpg" \) | sort)

if (( ${#WALLPAPERS[@]} == 0 )); then
  notify-send "Wallpaper" "No wallpapers found"
  exit 1
fi

if (( ${#WALLPAPERS[@]} == 1 )); then
  notify-send "Wallpaper" "Only one wallpaper in this theme"
  exit 0
fi

MODE="${1:-pick}"

if [[ $MODE == "apply" ]]; then
  # Direct apply from path (used by rofi script mode)
  SELECTED="$2"
elif [[ $MODE == "next" ]]; then
  # Find current index and cycle to next
  NEXT=0
  for i in "${!WALLPAPERS[@]}"; do
    if [[ "${WALLPAPERS[$i]}" == "$CURRENT" ]]; then
      NEXT=$(( (i + 1) % ${#WALLPAPERS[@]} ))
      break
    fi
  done
  SELECTED="${WALLPAPERS[$NEXT]}"
elif [[ $MODE == "pick" ]]; then
  # Three columns, matching the theme picker. A theme ships at most four
  # wallpapers, so the last row is often short, and consistency with the theme
  # grid was preferred over a tidier final row.
  SELECTED=$("$HOME/.local/bin/hyprsimple-wallpaper-picker.sh" |
    "$HOME/.local/bin/hyprsimple-image-picker.sh" \
      --prompt "Wallpaper" --columns 3 --selected "$CURRENT")
  [[ -z $SELECTED ]] && exit 0
fi

if [[ ! -f $SELECTED ]]; then
  notify-send "Wallpaper" "File not found: $SELECTED"
  exit 1
fi

# Apply wallpaper (remove first then copy so hyprpaper detects change)
rm -f "$CACHE_DIR/current_wallpaper" "$CACHE_DIR/current_lockscreen.png"
cp "$SELECTED" "$CACHE_DIR/current_wallpaper"
cp "$SELECTED" "$CACHE_DIR/current_lockscreen.png"
echo "$SELECTED" > "$CACHE_DIR/current_wallpaper_path"

# Disable live wallpaper mode (manual pick overrides cycling)
rm -f "$CACHE_DIR/live_wallpaper_enabled"
write_hyprpaper_conf "$HOME/.cache/current_wallpaper"

# Reload hyprpaper
systemctl --user restart hyprpaper.service

notify-send "Wallpaper" "$(basename "$SELECTED")" -i "$SELECTED"
