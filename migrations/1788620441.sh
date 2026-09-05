echo "Remove the two dangling rofi theme links"

# install.sh tried to point ~/.config/rofi/launcher and .../powermenu at the
# active theme with `ln -sfn "$THEME_DIR/rofi/<type>" "$HOME/.config/rofi/<type>"`.
# Both halves were wrong. By that point ~/.config/rofi/launcher is a real
# directory, copied from the repository's .config/rofi, and `ln -s` given an
# existing directory writes the link inside it rather than replacing it, so what
# appeared was ~/.config/rofi/launcher/launcher. And no theme has ever shipped a
# rofi/ directory, so the target did not exist and the link dangled from birth.
#
# They were never read. theme-switcher.sh themes rofi by writing images/ and
# patching style.rasi inside the real directories.
#
# Only a link that does not resolve and points into a theme's rofi/ is removed.
# Anything else in that spot belongs to whoever put it there.

for type in launcher powermenu; do
  link="$HOME/.config/rofi/$type/$type"

  [[ -L $link ]] || continue
  [[ -e $link ]] && continue

  target=$(readlink "$link")
  case "$target" in
    */themes/*/rofi/"$type") ;;
    *) continue ;;
  esac

  rm -f "$link"
  echo "  Removed $link"
  echo "  It pointed at $target, which no theme has."
done
