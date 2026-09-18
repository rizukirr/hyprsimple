echo "Give the bar its transparency back"

# The previous release made waybar's own window carry the theme background, so
# the bar would stop taking its colour from whatever the top strip of the
# wallpaper happened to be. Seen on a real desktop it was worse than the problem:
# a solid slab across the top, where the whole point of the bar sitting over the
# wallpaper was that it does not look like one. It is transparent again, and a
# bar that matches the terminal is a line away, written beside the setting.
#
# This undoes the change only where that release put it, which is the exact line
# it wrote, and the shipped comment above it if a config refresh brought that in
# too. Anything else in the block is yours and is left alone with the line to
# set printed.

STYLE="$HOME/.config/waybar/style.css"
OLD="  background: @bg-deep;"
NEW="  background: transparent;"

if [[ ! -f $STYLE ]]; then
  echo "  No waybar style here, so there is nothing to change."
  exit 0
fi

# Anchored to the #waybar block, because a background of the theme colour
# elsewhere in the file is a rule of your own and not this one.
block_has() {
  awk -v want="$1" '
    /^#waybar[[:space:]]*\{/ { inside = 1; next }
    inside && /^\}/ { inside = 0 }
    inside && $0 == want { found = 1 }
    END { exit (found ? 0 : 1) }
  ' "$STYLE"
}

if block_has "$NEW"; then
  echo "  The bar is transparent already."
  exit 0
fi

if ! block_has "$OLD"; then
  echo "  Your #waybar block is your own, so it was left alone."
  echo "  To have the wallpaper through the bar again, set this inside #waybar in $STYLE:"
  echo "    $NEW"
  exit 0
fi

tmp=$(mktemp) || exit 1
awk -v old="$OLD" -v new="$NEW" '
  /^#waybar[[:space:]]*\{/ { inside = 1; print; next }
  inside && /^\}/ { inside = 0; print; next }
  # The comment that shipped above the line, and nothing else that looks like a
  # comment, so a note of your own in the block survives.
  inside && /^[[:space:]]*\/\* The bar carries the theme.s own background/ { comment = 1 }
  comment { if ($0 ~ /\*\//) { comment = 0 } next }
  inside && $0 == old { print new; next }
  { print }
' "$STYLE" >"$tmp"

# Written back into the same file rather than moved over it, so its permissions
# and anything linking to it stay as they were.
cat "$tmp" >"$STYLE"
rm -f "$tmp"

echo "  The bar shows the wallpaper through it again."
echo "  For the theme's colour instead, set: background: @bg-deep;"

# waybar reads its style at start, so without this the change waits for the next
# login and looks like nothing happened.
if [[ -x $HOME/.local/bin/hyprsimple-restart-waybar.sh ]]; then
  "$HOME/.local/bin/hyprsimple-restart-waybar.sh" --if-running &>/dev/null || true
fi
