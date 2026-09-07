#!/bin/bash

source "$HOME/.local/bin/hypr-helpers.sh"
source "$HOME/.local/bin/hyprsimple-theme-deliver.sh"

# Usage: theme-switcher.sh [theme-name]
#   No argument: show rofi picker
#   With argument: apply theme directly (used by rofi script mode)

THEMES_DIR="$HOME/.config/hypr/themes"
CACHE_DIR="$HOME/.cache"
mkdir -p "$CACHE_DIR"

if [[ -n "$1" ]]; then
  THEME="$1"
else
  THEME=$("$HOME/.local/bin/hyprsimple-theme-picker.sh" |
    "$HOME/.local/bin/hyprsimple-image-picker.sh" --prompt "Theme" --columns 3)
fi
[[ -z "$THEME" ]] && exit 0

THEME_PATH="$THEMES_DIR/$THEME"

# 1. Generate configs from templates (if colors.toml exists)
if [[ -f "$THEME_PATH/colors.toml" ]]; then
  "$HOME/.local/bin/theme-apply-templates.sh" "$THEME_PATH"
fi

# 2 to 8. Every generated file the theme ships, put where its program reads it.
#
# Shared with hyprsimple-update.sh, which re-renders the templates when one
# changes and has to deliver the result the same way. It used to carry its own
# shorter list and so delivered two of the eight.
deliver_theme_configs "$THEME_PATH"

# 9. Wallpaper (copy so hyprpaper detects change)
WALLPAPER=""
if [[ -d "$THEME_PATH/backgrounds" ]]; then
  WALLPAPER=$(find "$THEME_PATH/backgrounds" -type f \( -name "*.png" -o -name "*.jpg" \) | sort | head -1)
elif [[ -f "$THEME_PATH/wallpaper.jpg" ]]; then
  WALLPAPER="$THEME_PATH/wallpaper.jpg"
fi
if [[ -n "$WALLPAPER" ]]; then
  rm -f "$CACHE_DIR/current_wallpaper"
  cp "$WALLPAPER" "$CACHE_DIR/current_wallpaper"
  echo "$WALLPAPER" > "$CACHE_DIR/current_wallpaper_path"

  # Use theme background as rofi launcher/powermenu image
  WP_EXT="${WALLPAPER##*.}"
  for rofi_type in launcher powermenu; do
    ROFI_TARGET="$HOME/.config/rofi/$rofi_type/images"
    mkdir -p "$ROFI_TARGET"
    [[ -L "$ROFI_TARGET" ]] && rm -f "$ROFI_TARGET" && mkdir -p "$ROFI_TARGET"
    rm -f "$ROFI_TARGET"/wallpaper.*
    ln -sf "$WALLPAPER" "$ROFI_TARGET/wallpaper.$WP_EXT"
    sed -i "s|images/wallpaper\.[a-z]*|images/wallpaper.$WP_EXT|" "$HOME/.config/rofi/$rofi_type/style.rasi"
  done
fi

# Write hyprpaper.conf based on live wallpaper state
if [[ -f "$CACHE_DIR/live_wallpaper_enabled" && -d "$THEME_PATH/backgrounds" ]]; then
  write_hyprpaper_conf "$THEME_PATH/backgrounds" 30
else
  write_hyprpaper_conf "$HOME/.cache/current_wallpaper"
fi

# Lockscreen. The cache filename keeps its .png suffix because hyprlock.conf
# points at it by name. Hyprlock sniffs content, so a JPEG behind that name is
# fine, and the fallback below has always written one.
rm -f "$CACHE_DIR/current_lockscreen.png"
THEME_LOCKSCREEN=$(find "$THEME_PATH" -maxdepth 1 -type f -name 'lockscreen.*' | sort | head -1)
if [[ -n "$THEME_LOCKSCREEN" ]]; then
  cp "$THEME_LOCKSCREEN" "$CACHE_DIR/current_lockscreen.png"
elif [[ -n "$WALLPAPER" ]]; then
  cp "$WALLPAPER" "$CACHE_DIR/current_lockscreen.png"
fi

# 10. GTK/QT light/dark mode + Icon/Cursor settings
if [[ -f "$THEME_PATH/light.mode" ]]; then
  GTK_THEME_NAME="Adwaita"
  gsettings set org.gnome.desktop.interface color-scheme "prefer-light"
else
  GTK_THEME_NAME="Adwaita-dark"
  gsettings set org.gnome.desktop.interface color-scheme "prefer-dark"
fi

gsettings set org.gnome.desktop.interface gtk-theme "$GTK_THEME_NAME"

# Update gtk-3.0 and gtk-4.0 settings.ini (some apps read these instead of gsettings)
for gtk_dir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
  mkdir -p "$gtk_dir"
  if [[ -f "$gtk_dir/settings.ini" ]]; then
    sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$GTK_THEME_NAME/" "$gtk_dir/settings.ini"
  fi
done

# Icon theme (icons.theme = omarchy style, icon-theme = hyprsimple style)
if [[ -f "$THEME_PATH/icons.theme" ]]; then
  gsettings set org.gnome.desktop.interface icon-theme "$(cat "$THEME_PATH/icons.theme")"
elif [[ -f "$THEME_PATH/icon-theme" ]]; then
  gsettings set org.gnome.desktop.interface icon-theme "$(cat "$THEME_PATH/icon-theme")"
fi

# Replace one export in uwsm/env rather than appending another. The file is
# read once at login, so a second export of the same name would win silently
# and the file would grow a line per theme switch.
set_session_env() {
  local name="$1" value="$2"
  local file="$HOME/.config/uwsm/env"
  [[ -f $file ]] || return 0
  local tmp="$file.tmp.$$"
  grep -v "^export $name=" "$file" >"$tmp" || true
  printf 'export %s=%s\n' "$name" "$value" >>"$tmp"
  mv "$tmp" "$file"
}

if [[ -f "$THEME_PATH/cursor-theme" ]]; then
  CURSOR="$(cat "$THEME_PATH/cursor-theme")"
  gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR"
  [[ -z "$THEME_SWITCHER_NO_RELOAD" ]] && hyprctl setcursor "$CURSOR" 24

  # gsettings reaches GTK and `hyprctl setcursor` reaches Hyprland, but only
  # until logout. XCURSOR_THEME is what survives a login and what XWayland, SDL
  # and Qt read, and nothing here ever wrote it: install.sh wrote it once, and
  # only if the theme it installed with declared a cursor. The default theme is
  # deep-sea, which does not, so on a fresh install it was never set at all,
  # and switching to a theme that does declare one did not set it either.
  set_session_env XCURSOR_THEME "$CURSOR"
fi

# 11. Reload Services (skipped during install via THEME_SWITCHER_NO_RELOAD=1)
if [[ -z "$THEME_SWITCHER_NO_RELOAD" ]]; then
  hyprctl reload

  systemctl --user restart hyprpaper.service

  "$HOME/.local/bin/hyprsimple-restart-waybar.sh" --if-running

  "$HOME/.local/bin/hyprsimple-restart-dunst.sh" --if-running

  notify-send "Theme Manager" "Theme '$THEME' applied!" -i "$CACHE_DIR/current_wallpaper"
fi
