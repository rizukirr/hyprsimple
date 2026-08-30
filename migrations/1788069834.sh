echo "Refresh the dunst colour template so the global frame colour tracks the theme"

# hyprsimple's dunst template gained a [global] section, but templates live in
# ~/.config, which updates never overwrite. Without this the change reaches new
# installs and nobody else.
#
# The rendered output under each theme's generated/ is build output, so it is
# rebuilt rather than migrated. The drop-in for the theme you are on is
# refreshed too, so the change is visible without switching themes first.

TPL="$HOME/.config/hypr/themes/templates/dunst-colors.tpl"
SHIPPED_TPL="$HYPRSIMPLE_PATH/.config/hypr/themes/templates/dunst-colors.tpl"

[[ -f $SHIPPED_TPL ]] || exit 0

if [[ ! -f $TPL ]] || ! cmp -s "$TPL" "$SHIPPED_TPL"; then
  "$HOME/.local/bin/hyprsimple-refresh-config.sh" hypr/themes/templates/dunst-colors.tpl
fi

# Rebuild the rendered output for the theme currently applied, and refresh its
# drop-in. current_wallpaper_path is the only record of which theme that is, so
# this is skipped rather than guessed when it is absent.
WP_PATH="$HOME/.cache/current_wallpaper_path"
if [[ -f $WP_PATH ]]; then
  theme_dir=$(dirname "$(dirname "$(cat "$WP_PATH")")")
  if [[ -f "$theme_dir/colors.toml" ]]; then
    "$HOME/.local/bin/theme-apply-templates.sh" "$theme_dir" >/dev/null
    if [[ -f "$theme_dir/generated/dunst-colors" ]]; then
      mkdir -p "$HOME/.config/dunst/dunstrc.d"
      cp "$theme_dir/generated/dunst-colors" "$HOME/.config/dunst/dunstrc.d/90-theme.conf"
      echo "Refreshed dunstrc.d/90-theme.conf from $(basename "$theme_dir")"
    fi
  fi
fi

if pgrep -x dunst >/dev/null; then
  pkill dunst
  uwsm app -- dunst >/dev/null 2>&1 &
fi
