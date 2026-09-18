echo "Replace the borrowed themes with the well known colorschemes"

# ~/.config/hypr/themes is copied once at install and never touched again, so a
# theme added later reaches nobody and a theme dropped later stays for ever.
# This syncs the two directions:
#
#   added    every theme hyprsimple ships that you do not have is copied in.
#            A theme you already have is left exactly as it is, including one
#            of your own that hyprsimple knows nothing about.
#
#   removed  the eight themes that came from omarchy are deleted, and only
#            where their colors.toml is still byte-identical to the one
#            hyprsimple shipped, which proves you never edited it.
#
# If the theme in use is one of the removed ones, deep-sea is applied, because
# the rofi, waybar and hypr colour files are symlinks into the theme directory
# and deleting it underneath them leaves every one of them dangling.

THEMES="$HOME/.config/hypr/themes"
SHIPPED="$HYPRSIMPLE_PATH/.config/hypr/themes"

# md5 of each removed theme's colors.toml as hyprsimple shipped it.
REMOVED="
  ethereal 46016f3ef7ee01c093dd5ba74c0a02dc
  hackerman 5407e6d5aaf6b1f39278a33ef2b294db
  matte-black c5de6473cfc385bf67c47e44124ca35f
  miasma d4fc929a5acf844d01d658e6141576fa
  osaka-jade f6c1afa2595fff13a8c1713783984300
  ristretto de95cfb4beb123ae8fe572ff789e0a17
  vantablack 64c29a1dc9d1dcc9903da0185565c347
  white 4b865bd36be4cf81f9a263e31ac56853
"

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

added=0
for dir in "$SHIPPED"/*/; do
  name=$(basename "$dir")
  [[ $name == templates* ]] && continue
  [[ -e "$THEMES/$name" ]] && continue
  cp -r "$dir" "$THEMES/$name"
  added=$((added + 1))
done
((added > 0)) && echo "  Added $added theme(s)."

removed=0
kept=()
active_removed=""
while read -r name sum; do
  [[ -n $name ]] || continue
  target="$THEMES/$name"
  [[ -d $target ]] || continue

  if [[ ! -f $target/colors.toml ]] ||
    [[ $(md5sum "$target/colors.toml" | cut -d' ' -f1) != "$sum" ]]; then
    kept+=("$name")
    continue
  fi

  rm -rf "$target"
  removed=$((removed + 1))
  [[ $active == "$name" ]] && active_removed="$name"
done <<<"$REMOVED"

((removed > 0)) && echo "  Removed $removed theme(s) that came from omarchy."

if ((${#kept[@]} > 0)); then
  echo "  Left alone, because you have your own version:"
  printf '    %s\n' "${kept[@]}"
fi

# Applied rather than only written down. The colour files are symlinks into the
# theme that was just deleted, so leaving it is a broken desktop.
if [[ -n $active_removed ]]; then
  if [[ -x $HOME/.local/bin/theme-switcher.sh ]]; then
    if systemctl --user is-active graphical-session.target &>/dev/null; then
      "$HOME/.local/bin/theme-switcher.sh" deep-sea &>/dev/null || true
    else
      THEME_SWITCHER_NO_RELOAD=1 "$HOME/.local/bin/theme-switcher.sh" deep-sea &>/dev/null || true
    fi
    echo "  You were using $active_removed, which is gone, so deep-sea was applied."
  else
    echo "  You were using $active_removed, which is gone. Press SUPER + SHIFT + T to pick another."
  fi
fi

if ((added == 0 && removed == 0 && ${#kept[@]} == 0)); then
  echo "  Nothing to do."
fi
