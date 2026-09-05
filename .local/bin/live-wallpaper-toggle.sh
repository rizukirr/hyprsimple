#!/bin/bash

# Toggle live wallpaper (hyprpaper directory cycling)
# When ON: hyprpaper cycles through theme backgrounds every 30s
# When OFF: hyprpaper shows a single static wallpaper

CACHE_DIR="$HOME/.cache"
FLAG="$CACHE_DIR/live_wallpaper_enabled"

source "$HOME/.local/bin/hypr-helpers.sh"

# Derive backgrounds dir from current wallpaper path
CURRENT_PATH=$(cat "$CACHE_DIR/current_wallpaper_path" 2>/dev/null)
THEME_DIR=$(dirname "$(dirname "$CURRENT_PATH")" 2>/dev/null)
BG_DIR="$THEME_DIR/backgrounds"

if [[ ! -d "$BG_DIR" ]]; then
  notify-send "Live Wallpaper" "No backgrounds folder found for current theme"
  exit 1
fi

ACTION="$1"

turn_off() {
  # Try to get current wallpaper from hyprpaper IPC
  ACTIVE=$(hyprctl hyprpaper listactive 2>/dev/null | head -1)
  # Parse: hyprpaper answers "monitor: /path/to/wallpaper". It was read here as
  # "monitor = /path", so the strip matched nothing, the path kept its "eDP-1: "
  # prefix, the -f check below rejected it, and every disable fell back to the
  # cached wallpaper. That is the exact staleness this lookup exists to avoid.
  RESOLVED="${ACTIVE#*: }"

  # Validate resolved path exists and is inside the theme backgrounds dir
  if [[ ! -f "$RESOLVED" || "$RESOLVED" != "$BG_DIR"/* ]]; then
    # Fallback to cached path
    RESOLVED="$CURRENT_PATH"
  fi

  if [[ -f "$RESOLVED" ]]; then
    rm -f "$CACHE_DIR/current_wallpaper"
    cp "$RESOLVED" "$CACHE_DIR/current_wallpaper"
    echo "$RESOLVED" > "$CACHE_DIR/current_wallpaper_path"
  fi

  write_hyprpaper_conf "$HOME/.cache/current_wallpaper"
  rm -f "$FLAG"
  systemctl --user restart hyprpaper.service
  notify-send "Live Wallpaper" "Disabled" -i "$CACHE_DIR/current_wallpaper"
}

turn_on() {
  write_hyprpaper_conf "$BG_DIR" 30
  touch "$FLAG"
  systemctl --user restart hyprpaper.service
  notify-send "Live Wallpaper" "Enabled (30s cycle)" -i "$CACHE_DIR/current_wallpaper"
}

case "$ACTION" in
  apply)
    # Put hyprpaper in whatever state the flag already records, without
    # changing that state. This is what autostart wants at login.
    #
    # It used to run "on" there, which turned live wallpaper back on every
    # single login. Turning it off with SUPER+CTRL+W lasted until the next one,
    # and so did picking a wallpaper with SUPER+W, because that clears the same
    # flag to pin the choice. A toggle whose state is reset at every login is
    # not a toggle.
    if [[ -f "$FLAG" ]]; then
      write_hyprpaper_conf "$BG_DIR" 30
    else
      write_hyprpaper_conf "$HOME/.cache/current_wallpaper"
    fi
    systemctl --user restart hyprpaper.service 2>/dev/null || true
    ;;
  on)
    # Skip if already on
    [[ -f "$FLAG" ]] && exit 0
    turn_on
    ;;
  off)
    # Skip if already off
    [[ ! -f "$FLAG" ]] && exit 0
    turn_off
    ;;
  *)
    # Toggle (original behavior)
    if [[ -f "$FLAG" ]]; then
      turn_off
    else
      turn_on
    fi
    ;;
esac
