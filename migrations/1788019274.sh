echo "Refresh theme files from the install"

# ~/.config/hypr/themes is copied at install time and nothing has ever refreshed
# it, so every existing install still carries the pre-slimming wallpapers: 123 MB
# against 18 MB for what hyprsimple now ships. The images are visually the same.
#
# Three rules, in order of caution:
#   - copy in anything the install ships that differs
#   - delete a local file only when the install clearly replaced it, meaning a
#     file with the same stem and a different extension now exists, or it is one
#     of the paths removed wholesale
#   - leave anything else alone, because it is probably the user's

SRC="$HYPRSIMPLE_PATH/.config/hypr/themes"
DST="$HOME/.config/hypr/themes"

[[ -d $SRC && -d $DST ]] || exit 0

copied=0
deleted=0
kept=()

for theme_dir in "$SRC"/*/; do
  theme=$(basename "$theme_dir")
  [[ -d "$DST/$theme" ]] || continue

  while IFS= read -r rel; do
    src="$SRC/$theme/$rel"
    dst="$DST/$theme/$rel"
    if [[ ! -f $dst ]] || ! cmp -s "$src" "$dst"; then
      mkdir -p "$(dirname "$dst")"
      cp -f "$src" "$dst"
      copied=$((copied + 1))
    fi
  done < <(cd "$SRC/$theme" && find . -type f -printf '%P\n')

  while IFS= read -r rel; do
    # generated/ is build output that theme-switcher reads. The repo never ships
    # it, so it would look removed, and deleting it would blank the live theme.
    [[ $rel == generated/* ]] && continue
    [[ -f "$SRC/$theme/$rel" ]] && continue

    stem="${rel%.*}"
    if compgen -G "$SRC/$theme/$stem.*" >/dev/null ||
       [[ $rel == rofi/* || $rel == lockscreen.png || $rel == wallpaper.jpg ]]; then
      rm -f "$DST/$theme/$rel"
      deleted=$((deleted + 1))
    else
      kept+=("$theme/$rel")
    fi
  done < <(cd "$DST/$theme" && find . -type f -printf '%P\n')

  find "$DST/$theme" -type d -empty -delete 2>/dev/null
done

echo "  Copied $copied file(s) from the install, removed $deleted superseded file(s)"

if ((${#kept[@]} > 0)); then
  echo "  Left ${#kept[@]} file(s) alone that hyprsimple does not ship, assuming they are yours"
fi

# hyprpaper holds the wallpaper open, and a file it is showing may have been
# replaced or renamed underneath it.
if systemctl --user is-active hyprpaper.service &>/dev/null; then
  systemctl --user restart hyprpaper.service
  echo "  Restarted hyprpaper"
fi
