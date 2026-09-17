echo "Stop the clipboard menu wiping the clipboard when it is dismissed"

# SUPER + V ran
#
#   sh -c 'cliphist list | rofi --show dmenu | cliphist decode | wl-copy'
#
# and pressing Escape replaced the clipboard with nothing. rofi printed nothing,
# cliphist decode printed nothing, and wl-copy copied it: wl-clipboard's manual
# names "wl-copy < /dev/null" as the way to put zero-sized data on the
# clipboard. hyprsimple-clipboard-menu.sh copies only when an entry was picked.
#
# The bind lives in applications.lua, which is yours. That one line is replaced
# only where it is still exactly the line hyprsimple shipped, which it was in
# every version, and the rest of the file is left as it is.

FILE="$HOME/.config/hypr/bindings/applications.lua"

OLD=$(cat <<'LINEEOF'
hl.bind("SUPER + V", hl.dsp.exec_cmd("sh -c 'cliphist list | rofi --show dmenu | cliphist decode | wl-copy'"),  { description = "Clipboard Manager" })
LINEEOF
)
NEW=$(cat <<'LINEEOF'
hl.bind("SUPER + V", hl.dsp.exec_cmd(home .. "/.local/bin/hyprsimple-clipboard-menu.sh"),  { description = "Clipboard Manager" })
LINEEOF
)

if [[ ! -f $FILE ]]; then
  echo "  No applications.lua here, so there is nothing to change."
  exit 0
fi

if grep -qxF "$NEW" "$FILE"; then
  echo "  SUPER + V already opens hyprsimple-clipboard-menu.sh."
  exit 0
fi

if ! grep -qxF "$OLD" "$FILE"; then
  echo "  Your SUPER + V line is your own, so it was left alone."
  echo "  To stop Escape wiping the clipboard, bind it to:"
  echo "    $NEW"
  exit 0
fi

tmp=$(mktemp) || exit 1
while IFS= read -r line || [[ -n $line ]]; do
  if [[ $line == "$OLD" ]]; then
    printf '%s\n' "$NEW"
  else
    printf '%s\n' "$line"
  fi
done <"$FILE" >"$tmp"

# Written back into the same file rather than moved over it, so its permissions
# and anything linking to it stay as they were.
cat "$tmp" >"$FILE"
rm -f "$tmp"

echo "  SUPER + V now opens hyprsimple-clipboard-menu.sh, which copies only when you pick an entry."
