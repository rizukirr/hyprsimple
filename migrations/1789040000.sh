echo "Let the bar carry the theme's background instead of the wallpaper"

# waybar's own window was transparent, so everything between the widgets was
# the wallpaper. The bar therefore took on whatever the top strip of the current
# image happened to be: cream on one wallpaper, grey on the next, and rarely
# anything like the terminal sitting under it. Reported as a bar that looked
# creamy while the terminal was dark, on a theme that is neither.
#
# style.css is yours, so this changes the one line and nothing else, and only
# where that line is still the one hyprsimple shipped. Anything else is left
# alone with the change printed.

STYLE="$HOME/.config/waybar/style.css"
OLD="  background: transparent;"
NEW="  background: @bg-deep;"

if [[ ! -f $STYLE ]]; then
  echo "  No waybar style here, so there is nothing to change."
  exit 0
fi

# The line appears inside the #waybar block. Other blocks set their own
# backgrounds, and none of them is transparent in any shipped version, but the
# edit is still anchored to that block so a style of your own cannot be caught
# by it.
block_has_transparent() {
  awk -v old="$OLD" '
    /^#waybar[[:space:]]*\{/ { inside = 1; next }
    inside && /^\}/ { inside = 0 }
    inside && $0 == old { found = 1 }
    END { exit (found ? 0 : 1) }
  ' "$STYLE"
}

if grep -qxF "$NEW" "$STYLE"; then
  echo "  The bar already carries the theme's background."
  exit 0
fi

if ! block_has_transparent; then
  echo "  Your #waybar block is your own, so it was left alone."
  echo "  To have the bar take the theme's background rather than the wallpaper,"
  echo "  set this inside #waybar in $STYLE:"
  echo "    $NEW"
  exit 0
fi

tmp=$(mktemp) || exit 1
awk -v old="$OLD" -v new="$NEW" '
  /^#waybar[[:space:]]*\{/ { inside = 1; print; next }
  inside && /^\}/ { inside = 0; print; next }
  inside && $0 == old { print new; next }
  { print }
' "$STYLE" >"$tmp"

# Written back into the same file rather than moved over it, so its permissions
# and anything linking to it stay as they were.
cat "$tmp" >"$STYLE"
rm -f "$tmp"

echo "  The bar now uses the theme's background."
echo "  For the wallpaper faintly through it, set: background: alpha(@bg-deep, 0.85);"

# Applied now where there is a bar to restart. waybar reads its style at start,
# so without this the change waits for the next login and looks like nothing
# happened.
if [[ -x $HOME/.local/bin/hyprsimple-restart-waybar.sh ]]; then
  "$HOME/.local/bin/hyprsimple-restart-waybar.sh" --if-running &>/dev/null || true
fi
