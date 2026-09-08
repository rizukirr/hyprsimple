echo "Add the recording menu's rofi stub"

# ~/.config/rofi is copied once at install and never touched again, so a menu
# added later has no stub on a machine that already exists and SUPER + R would
# open rofi with no theme at all: its built-in light default, on a dark
# desktop.
#
# The stub is the same shape as the other menus': one import of the shipped
# style through the hyprsimple symlink, and room underneath for the user's own
# settings. The style itself lives in default/rofi and updates on its own.

STUB_DIR="$HOME/.config/rofi/record"
STUB="$STUB_DIR/style.rasi"

if [[ -e $STUB ]]; then
  echo "  You already have $STUB, so it was left alone."
  exit 0
fi

if [[ ! -d $HOME/.config/rofi ]]; then
  echo "  No rofi config here, so there is nothing to add to."
  exit 0
fi

mkdir -p "$STUB_DIR"
cat >"$STUB" <<'STUBEOF'
@import "hyprsimple/record/style.rasi"

/* This file is yours. hyprsimple copies it once and never touches it again,
   so anything you change here stays changed. */

/* hyprsimple's default is imported above. Anything you set below wins,
   property by property, and anything you leave out keeps the default.
   Put your own settings here rather than above the import, because the
   later declaration is the one rofi uses. */
STUBEOF

echo "  Added $STUB, so SUPER + R opens the menu in your theme's colours."
