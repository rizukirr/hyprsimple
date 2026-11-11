echo "Add the hyprsimple theme, made from Hypri's colours"

# ~/.config/hypr/themes is copied once at install and never touched again, so a
# theme added later reaches nobody until a migration carries it. This copies the
# hyprsimple theme in when it is missing. It does not switch to it: the theme
# you are using is your choice, and SUPER + SHIFT + T offers the new one.
#
# hyprsimple is the default for new installs, which get it from install.sh.

THEMES="$HOME/.config/hypr/themes"
SHIPPED="$HYPRSIMPLE_PATH/.config/hypr/themes/hyprsimple"

if [[ ! -d $THEMES ]]; then
  echo "  No themes directory here, so there is nothing to add to."
  exit 0
fi

if [[ ! -f $SHIPPED/colors.toml ]]; then
  echo "  This install does not ship the hyprsimple theme, so nothing was added."
  exit 0
fi

if [[ -e $THEMES/hyprsimple ]]; then
  echo "  You already have a theme named hyprsimple, so it was left as it is."
  exit 0
fi

# Copied under a temporary name and moved into place, so a copy cut short leaves
# no half theme behind for the picker to list. A leftover from an interrupted
# run is cleared first, which keeps this safe to run again.
rm -rf "$THEMES/.hyprsimple.partial"
cp -r "$SHIPPED" "$THEMES/.hyprsimple.partial" || exit 1
mv "$THEMES/.hyprsimple.partial" "$THEMES/hyprsimple" || exit 1

if [[ ! -f $THEMES/hyprsimple/colors.toml ]] || ! compgen -G "$THEMES/hyprsimple/backgrounds/*" >/dev/null; then
  echo "  The hyprsimple theme did not copy completely." >&2
  exit 1
fi

echo "  Added it. Press SUPER + SHIFT + T to try it."
