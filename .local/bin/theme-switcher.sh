#!/bin/bash

source "$HOME/.local/bin/hypr-helpers.sh"

# Usage: theme-switcher.sh [theme-name]
#   No argument: show rofi picker
#   With argument: apply theme directly (used by rofi script mode)

THEMES_DIR="$HOME/.config/hypr/themes"
CACHE_DIR="$HOME/.cache"
mkdir -p "$CACHE_DIR"

if [[ -n "$1" ]]; then
  THEME="$1"
else
  THEME=$(ls "$THEMES_DIR" | grep -v templates | rofi -dmenu -p "Select Theme:")
fi
[[ -z "$THEME" ]] && exit 0

THEME_PATH="$THEMES_DIR/$THEME"

# 1. Generate configs from templates (if colors.toml exists)
if [[ -f "$THEME_PATH/colors.toml" ]]; then
  "$HOME/.local/bin/theme-apply-templates.sh" "$THEME_PATH"
fi

GEN="$THEME_PATH/generated"

# 2. Update Hyprland colors
if [[ -f "$GEN/hyprland-colors.lua" ]]; then
  ln -sf "$GEN/hyprland-colors.lua" "$HOME/.config/hypr/theme-active.lua"
elif [[ -f "$THEME_PATH/hypr/colors.lua" ]]; then
  ln -sf "$THEME_PATH/hypr/colors.lua" "$HOME/.config/hypr/theme-active.lua"
fi

# 3. Update Waybar colors
if [[ -f "$GEN/waybar-colors.css" ]]; then
  ln -sf "$GEN/waybar-colors.css" "$HOME/.config/waybar/theme-active.css"
elif [[ -f "$THEME_PATH/waybar/colors.css" ]]; then
  ln -sf "$THEME_PATH/waybar/colors.css" "$HOME/.config/waybar/theme-active.css"
fi

# 3b. Update Waybar clock module (themed calendar)
if [[ -f "$GEN/theme-clock.jsonc" ]]; then
  ln -sf "$GEN/theme-clock.jsonc" "$HOME/.config/waybar/theme-clock.jsonc"
elif [[ -f "$THEME_PATH/waybar/theme-clock.jsonc" ]]; then
  ln -sf "$THEME_PATH/waybar/theme-clock.jsonc" "$HOME/.config/waybar/theme-clock.jsonc"
fi

# 4. Update Rofi colors
if [[ -f "$GEN/rofi-colors.rasi" ]]; then
  ln -sf "$GEN/rofi-colors.rasi" "$HOME/.config/rofi/rofi-colors.rasi"
fi

# 5. Update Ghostty theme
GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
if [[ -f "$GHOSTTY_CONFIG" ]]; then
  # Remove old color/palette/theme lines, keep non-color settings
  grep -vE '^(background|foreground|cursor-color|cursor-text|selection-background|selection-foreground|palette|theme) =' "$GHOSTTY_CONFIG" > "$GHOSTTY_CONFIG.tmp"

  if [[ -f "$THEME_PATH/ghostty-theme" ]]; then
    # Use Ghostty's built-in theme
    echo "theme = $(cat "$THEME_PATH/ghostty-theme")" >> "$GHOSTTY_CONFIG.tmp"
  elif [[ -f "$GEN/ghostty.conf" ]]; then
    # Fallback to template-generated colors
    cat "$GEN/ghostty.conf" >> "$GHOSTTY_CONFIG.tmp"
  fi

  mv "$GHOSTTY_CONFIG.tmp" "$GHOSTTY_CONFIG"

  # Reload Ghostty config
  busctl --user call com.mitchellh.ghostty /com/mitchellh/ghostty org.gtk.Actions Activate "sava{sv}" "reload-config" 0 0 2>/dev/null
fi

# 6. Update Hyprlock theme colors
if [[ -f "$GEN/hyprlock.conf" ]]; then
  cp "$GEN/hyprlock.conf" "$HOME/.config/hypr/theme-hyprlock.conf"
fi

# 7. Update Dunst colors
if [[ -f "$GEN/dunst-colors" ]]; then
  DUNST_CONFIG="$HOME/.config/dunst/dunstrc"
  if [[ -f "$DUNST_CONFIG" ]]; then
    # Extract colors from generated file
    LOW_BG=$(sed -n '/urgency_low/,/urgency_normal/{/background/s/.*"\(.*\)".*/\1/p}' "$GEN/dunst-colors")
    LOW_FG=$(sed -n '/urgency_low/,/urgency_normal/{/foreground/s/.*"\(.*\)".*/\1/p}' "$GEN/dunst-colors")
    LOW_FC=$(sed -n '/urgency_low/,/urgency_normal/{/frame_color/s/.*"\(.*\)".*/\1/p}' "$GEN/dunst-colors")
    NORM_FC=$(sed -n '/urgency_normal/,/urgency_critical/{/frame_color/s/.*"\(.*\)".*/\1/p}' "$GEN/dunst-colors")
    CRIT_FC=$(sed -n '/urgency_critical/,${/frame_color/s/.*"\(.*\)".*/\1/p}' "$GEN/dunst-colors")

    # Replace in dunstrc (all urgency levels share bg/fg, differ by frame_color)
    sed -i "s/frame_color = \"#[a-fA-F0-9]*\"/frame_color = \"$LOW_FC\"/1" "$DUNST_CONFIG"
    sed -i "/\[urgency_normal\]/,/\[/{s/frame_color = \".*\"/frame_color = \"$NORM_FC\"/}" "$DUNST_CONFIG"
    sed -i "/\[urgency_critical\]/,/\[/{s/frame_color = \".*\"/frame_color = \"$CRIT_FC\"/}" "$DUNST_CONFIG"
    sed -i "s/background = \"#[a-fA-F0-9]*\"/background = \"$LOW_BG\"/g" "$DUNST_CONFIG"
    sed -i "s/foreground = \"#[a-fA-F0-9]*\"/foreground = \"$LOW_FG\"/g" "$DUNST_CONFIG"
  fi
fi

# 8. Update btop theme
if [[ -f "$GEN/btop.theme" ]]; then
  mkdir -p "$HOME/.config/btop/themes"
  cp "$GEN/btop.theme" "$HOME/.config/btop/themes/current.theme"
fi

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

if [[ -f "$THEME_PATH/cursor-theme" ]]; then
  CURSOR="$(cat "$THEME_PATH/cursor-theme")"
  gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR"
  [[ -z "$THEME_SWITCHER_NO_RELOAD" ]] && hyprctl setcursor "$CURSOR" 24
fi

# 11. Reload Services (skipped during install via THEME_SWITCHER_NO_RELOAD=1)
if [[ -z "$THEME_SWITCHER_NO_RELOAD" ]]; then
  hyprctl reload

  systemctl --user restart hyprpaper.service

  if pgrep -x waybar > /dev/null; then
    pkill waybar; sleep 0.1; uwsm app -- waybar &
  fi

  if pgrep -x dunst > /dev/null; then
    pkill dunst; uwsm app -- dunst &
  fi

  notify-send "Theme Manager" "Theme '$THEME' applied!" -i "$CACHE_DIR/current_wallpaper"
fi
