echo "Remove rofi, now that every menu is a panel of the bar"

# The launcher, the clipboard history, the theme and wallpaper pickers, the
# recording menu and the keybindings viewer are all panels of the bar. Nothing
# hyprsimple ships starts rofi any more, so it is no longer installed, and its
# configs, colour template and helper scripts are gone from the install.
#
# An update cannot finish that on a machine that already has them:
#
# The update never removes a script from ~/.local/bin, so the two that existed
# only for rofi stay behind.
#
# Two links under ~/.config/rofi pointed into the install. What they pointed at
# is gone, so they dangle.
#
# And the package stays installed until something removes it.
#
# The rest of ~/.config/rofi is yours and is left where it is. Nothing
# hyprsimple ships reads it any more.

ROFI_DIR="$HOME/.config/rofi"
HYPR_DIR="$HOME/.config/hypr"

# A binding or script of your own may still call rofi, or the helper that
# closed an open rofi menu. Those files are yours and are not rewritten, so
# when one is found the package and the helper are both left in place.
mine=()
if [[ -d $HYPR_DIR ]]; then
  while IFS= read -r file; do
    mine+=("$file")
  done < <(grep -rlE --include='*.lua' --include='*.conf' --include='*.sh' \
    '(^|[^a-zA-Z_-])rofi([^a-zA-Z_-]|$)|hyprsimple-menu-exclusive\.sh' "$HYPR_DIR" 2>/dev/null)
fi

for link in "$ROFI_DIR/hyprsimple" "$ROFI_DIR/rofi-colors.rasi"; do
  if [[ -L $link ]]; then
    rm -f "$link"
    echo "  Removed the link $link"
  fi
done

# Nothing calls the image picker, so it goes either way.
rm -f "$HOME/.local/bin/hyprsimple-image-picker.sh"

if ((${#mine[@]} > 0)); then
  echo "  These files of yours still call rofi, so the rofi package is left installed:"
  printf '    %s\n' "${mine[@]}"
  echo "  hyprsimple no longer themes rofi or ships a config for it."
  exit 0
fi

rm -f "$HOME/.local/bin/hyprsimple-menu-exclusive.sh"

# Asked for only when there is something to remove, so a machine without rofi
# never reaches sudo. -Rs and not -Rns: ~/.config/rofi is not the package's and
# is untouched either way. A removal that fails, or one pacman refuses because
# another package needs rofi, is reported and does not stop the update.
if pacman -Qi rofi >/dev/null 2>&1; then
  if sudo pacman -Rs --noconfirm rofi >/dev/null 2>&1; then
    echo "  Removed the rofi package."
  else
    echo "  Could not remove the rofi package. Remove it with: sudo pacman -Rs rofi"
  fi
fi

exit 0
