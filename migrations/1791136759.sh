echo "Replace the rosepine wallpaper"

# rosepine ships a new wallpaper, 0-rosepine.jpg, in place of 0-with-you.jpg.
# ~/.config/hypr/themes is copied at install time and an update never writes to
# it, so an existing install kept the old picture and never got the new one.
#
# The new one is copied in. The old one is removed only when it is byte for
# byte the file hyprsimple shipped: a picture of your own that happens to carry
# that name is left where it is.
#
# When rosepine is the theme in use, it is applied again so the new wallpaper
# is what is on screen, on the lock screen and in the pickers.

SRC="$HYPRSIMPLE_PATH/.config/hypr/themes/rosepine/backgrounds/0-rosepine.jpg"
DST_DIR="$HOME/.config/hypr/themes/rosepine/backgrounds"
OLD="$DST_DIR/0-with-you.jpg"
OLD_SHA="810bd74bcd9a52c25624731106e0e7978093ba87a47878ca17e71b8bf8b6aef3"

if [[ ! -f $SRC || ! -d $DST_DIR ]]; then
  echo "  No rosepine theme here, so there is nothing to replace."
  exit 0
fi

changed=no

if ! cmp -s "$SRC" "$DST_DIR/0-rosepine.jpg"; then
  cp -f "$SRC" "$DST_DIR/0-rosepine.jpg"
  echo "  Copied the new wallpaper."
  changed=yes
fi

if [[ -f $OLD ]]; then
  if [[ $(sha256sum "$OLD" | cut -d' ' -f1) == "$OLD_SHA" ]]; then
    rm -f "$OLD"
    echo "  Removed the old one."
    changed=yes
  else
    echo "  $OLD is not the picture hyprsimple shipped, so it is left where it is."
  fi
fi

if [[ $changed == no ]]; then
  echo "  Nothing to do."
  exit 0
fi

# Only when rosepine is what is in use. Applying it otherwise would switch the
# desktop to a theme nobody asked for.
active=$(readlink "$HOME/.config/hypr/theme-active.lua" 2>/dev/null)
if [[ $active == */themes/rosepine/* && -x $HOME/.local/bin/theme-switcher.sh ]]; then
  if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    "$HOME/.local/bin/theme-switcher.sh" rosepine >/dev/null 2>&1
  else
    # No session to reload, so only the files are put right for the next login.
    THEME_SWITCHER_NO_RELOAD=1 "$HOME/.local/bin/theme-switcher.sh" rosepine >/dev/null 2>&1
  fi
  echo "  rosepine is the theme in use, so it was applied again."
fi

exit 0
