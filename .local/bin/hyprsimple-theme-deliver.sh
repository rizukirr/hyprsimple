#!/bin/bash

# Puts a theme's generated files where the programs that read them look.
#
# Sourced by both callers, because there are two and they disagreed. A theme
# switch delivered all eight generated files. hyprsimple-update.sh re-rendered
# every theme when a template changed and then copied two of them, so a change
# to btop.theme.tpl or ghostty.conf.tpl was rendered, stamped as done, and
# never reached the program it was for until the user happened to switch theme.
# The update's own comment said "a template change now reaches every theme on
# the next update, so no future template needs a migration to deliver it",
# which was true of six templates out of eight.
#
# One function, so a template added later is delivered by both or by neither.
#
# Delivery only. The wallpaper, the GTK and icon settings and the reloads stay
# with their callers: switching theme should change the wallpaper, and an
# update should not.

deliver_theme_configs() {
  local THEME_PATH="$1"
  local GEN="$THEME_PATH/generated"

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
  local GHOSTTY_CONFIG="$HOME/.config/ghostty/config"
  if [[ -f "$GHOSTTY_CONFIG" ]]; then
    # Remove old color/palette/theme lines, keep non-color settings.
    #
    # The whitespace is matched the way ghostty matches it, not the way
    # hyprsimple happens to write it. This pattern required exactly "key = ", so
    # a line written any other way ghostty accepts survived every theme switch:
    #
    #   theme=gruvbox        kept, and "theme = kanagawa" appended after it
    #   theme  =  gruvbox    kept
    #     theme = gruvbox    kept
    #
    # All three validate, checked with `ghostty +validate-config`. The header of
    # the shipped config promises these lines are removed and rewritten, so
    # someone who set their own theme was told it would be replaced and instead
    # kept a dead line they could no longer see taking effect.
    grep -vE '^[[:space:]]*(background|foreground|cursor-color|cursor-text|selection-background|selection-foreground|palette|theme)[[:space:]]*=' "$GHOSTTY_CONFIG" > "$GHOSTTY_CONFIG.tmp"

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
  # generated/dunst-colors is already valid dunst config, so it drops straight in
  # as an override. Drop-ins outrank the base dunstrc, and lexical order decides
  # between them, so 90-theme sits above hyprsimple's default and below the user's.
  local DUNST_DROPIN="$HOME/.config/dunst/dunstrc.d/90-theme.conf"
  mkdir -p "$(dirname "$DUNST_DROPIN")"
  if [[ -f "$GEN/dunst-colors" ]]; then
    cp "$GEN/dunst-colors" "$DUNST_DROPIN"
  else
    # This theme has no colors.toml, so there are no colours to apply. Drop the
    # previous theme's file rather than leaving its colours in force.
    rm -f "$DUNST_DROPIN"
  fi

  # 8. Update btop theme
  #
  # Copying the theme into place was never enough: btop only reads the file its
  # own config names, and nothing set that. hyprsimple installs btop, install.sh
  # creates the themes directory, every theme renders a btop.theme and every
  # switch copied one here, and btop.conf still said color_theme = "Default",
  # which is what btop writes for itself on first run. The themed btop has never
  # worked on any install.
  #
  # btop names a theme by its filename without the extension, so the file written
  # below is selected as "current".
  if [[ -f "$GEN/btop.theme" ]]; then
    mkdir -p "$HOME/.config/btop/themes"
    cp "$GEN/btop.theme" "$HOME/.config/btop/themes/current.theme"

    local BTOP_CONF="$HOME/.config/btop/btop.conf"
    if [[ ! -f $BTOP_CONF ]]; then
      # btop fills in every key it does not find, so naming the theme is enough.
      printf 'color_theme = "current"\n' >"$BTOP_CONF"
    elif grep -q '^color_theme = ' "$BTOP_CONF"; then
      # Replaced rather than appended: btop reads the file top to bottom and a
      # second assignment would win, and the file would grow a line per switch.
      sed -i 's|^color_theme = .*|color_theme = "current"|' "$BTOP_CONF"
    else
      printf 'color_theme = "current"\n' >>"$BTOP_CONF"
    fi
  fi
}
