echo "Give every theme its own wallpaper"

# The colorscheme catalogue arrived with one picture between them. Every theme
# without a wallpaper of its own held a symlink to deep-sea's instead, as a
# placeholder until there was one for each. There is now, so the placeholder is
# replaced by the theme's own wallpapers.
#
# ~/.config/hypr/themes is yours. A theme is touched only where its backgrounds
# hold nothing but that placeholder link, which is proof no picture of your own
# is in there. Anything else, including a wallpaper you added beside the link,
# is left as it is.

THEMES="$HOME/.config/hypr/themes"
SHIPPED="$HYPRSIMPLE_PATH/.config/hypr/themes"
PLACEHOLDER="0-deep-sea.jpg"

if [[ ! -d $THEMES ]]; then
  echo "  No themes directory here, so there is nothing to change."
  exit 0
fi

if [[ ! -d $SHIPPED ]]; then
  echo "  The shipped themes are missing from this install, so nothing was changed."
  exit 0
fi

# The theme in use, read from the symlink the theme switcher leaves behind
# rather than from a state file, because there is no state file.
active=""
for link in "$HOME/.config/rofi/rofi-colors.rasi" "$HOME/.config/waybar/theme-active.css"; do
  [[ -L $link ]] || continue
  target=$(readlink "$link")
  case "$target" in
  */themes/*)
    active="${target#*/themes/}"
    active="${active%%/*}"
    break
    ;;
  esac
done

replaced=0
active_replaced=""
for dir in "$SHIPPED"/*/; do
  name=$(basename "$dir")
  [[ $name == templates* ]] && continue

  bg="$THEMES/$name/backgrounds"
  [[ -d $bg ]] || continue

  # Exactly the placeholder and nothing else. -mindepth so the directory itself
  # is not counted, and no -type so the link counts as the entry it is.
  mapfile -t entries < <(find "$bg" -mindepth 1 -maxdepth 1 -printf '%f\n')
  ((${#entries[@]} == 1)) || continue
  [[ ${entries[0]} == "$PLACEHOLDER" && -L "$bg/$PLACEHOLDER" ]] || continue

  mapfile -t shipped_walls < <(find "$dir/backgrounds" -mindepth 1 -maxdepth 1 -type f)
  ((${#shipped_walls[@]} > 0)) || continue

  rm -f "$bg/$PLACEHOLDER"
  cp "${shipped_walls[@]}" "$bg/"
  replaced=$((replaced + 1))
  [[ $active == "$name" ]] && active_replaced="$name"
done

if ((replaced == 0)); then
  echo "  Every theme already has its own wallpaper."
  exit 0
fi

echo "  $replaced theme(s) now have their own wallpaper instead of deep-sea's."

# The wallpaper on screen is a copy in ~/.cache, so the desktop does not break
# when the placeholder goes. It does keep showing deep-sea until the theme is
# applied again, which looks like the migration did nothing.
if [[ -n $active_replaced && -x $HOME/.local/bin/theme-switcher.sh ]]; then
  if systemctl --user is-active graphical-session.target &>/dev/null; then
    "$HOME/.local/bin/theme-switcher.sh" "$active_replaced" &>/dev/null || true
  else
    THEME_SWITCHER_NO_RELOAD=1 "$HOME/.local/bin/theme-switcher.sh" "$active_replaced" &>/dev/null || true
  fi
  echo "  $active_replaced is the theme in use, so its wallpaper was applied."
fi
