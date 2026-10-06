echo "Leave the wallpaper one key, SUPER + SHIFT + W, and move the other two into its picker"

# Three keys worked the wallpaper: SUPER + SHIFT + W picked one, SUPER + ALT + W
# went to the next, and SUPER + CTRL + W turned live wallpaper on and off. The
# picker now has a switch for live wallpaper and a tile that adds a wallpaper
# from a file, so the two other keys are given up.
#
# They are bound in applications.lua, which is yours. A line is taken out only
# where it is still exactly the line hyprsimple shipped, which each of these
# was in every version, and the rest of the file is left as it is. A line you
# changed is yours and stays, and so does the script either key ran.

FILE="$HOME/.config/hypr/bindings/applications.lua"

NEXT_LINE=$(cat <<'LINEEOF'
hl.bind("SUPER + ALT + W",   hl.dsp.exec_cmd(home .. "/.local/bin/wallpaper-switcher.sh next"),        { description = "Next Wallpaper" })
LINEEOF
)
LIVE_LINE=$(cat <<'LINEEOF'
hl.bind("SUPER + CTRL + W",  hl.dsp.exec_cmd(home .. "/.local/bin/live-wallpaper-toggle.sh"),          { description = "Toggle Live Wallpaper" })
LINEEOF
)

if [[ ! -f $FILE ]]; then
  echo "  No applications.lua here, so there is nothing to change."
  exit 0
fi

removed=()
grep -qxF "$NEXT_LINE" "$FILE" && removed+=("SUPER + ALT + W")
grep -qxF "$LIVE_LINE" "$FILE" && removed+=("SUPER + CTRL + W")

if (( ${#removed[@]} > 0 )); then
  tmp=$(mktemp) || exit 1
  while IFS= read -r line || [[ -n $line ]]; do
    [[ $line == "$NEXT_LINE" || $line == "$LIVE_LINE" ]] && continue
    printf '%s\n' "$line"
  done <"$FILE" >"$tmp"

  # Written back into the same file rather than moved over it, so its
  # permissions and anything linking to it stay as they were.
  cat "$tmp" >"$FILE" || { rm -f "$tmp"; exit 1; }
  rm -f "$tmp"

  for key in "${removed[@]}"; do
    echo "  Removed $key."
  done
fi

# A key still bound here was changed by hand, or bound again somewhere else in
# the file. Said, since the README no longer lists it.
for key in "SUPER + ALT + W" "SUPER + CTRL + W"; do
  if grep -qF "\"$key\"" "$FILE"; then
    echo "  Your $key line is your own, so it was left alone."
  fi
done

echo "  SUPER + SHIFT + W opens the wallpaper picker, which now adds a wallpaper and switches live wallpaper on and off."
