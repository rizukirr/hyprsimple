echo "Refresh the theme picker's rofi style so the selection is visible"

# The picker marked its selection by filling the tile with @background-alt,
# which the theme template generates from color0. Across the sixteen shipped
# themes that sits under 1.5:1 against the panel in thirteen of them and is
# exactly the panel colour in four, so the selection could not be seen. It now
# takes a border in @selected, the accent, which is at least 3.86:1 everywhere.
#
# style.rasi lives in ~/.config, which updates never overwrite, so the change
# reaches new installs and nobody else without this.
#
# The file is only replaced when it is byte-identical to something hyprsimple
# shipped, which proves it was never edited.

ROFI="$HOME/.config/rofi"
user="$ROFI/theme-picker/style.rasi"
shipped="$HYPRSIMPLE_PATH/.config/rofi/theme-picker/style.rasi"

[[ -f $shipped ]] || exit 0

# Nobody has it yet: install it rather than skipping.
if [[ ! -f $user ]]; then
  mkdir -p "$ROFI/theme-picker"
  cp "$shipped" "$user"
  echo "Installed $user"
  exit 0
fi

cmp -s "$user" "$shipped" && exit 0

# md5 of every style.rasi hyprsimple has shipped
SHIPPED=(
  "c7933f90c1015e0c62229280ae097e8f"
  "e46ef3f79a8f839130a185fc8b45928d"
)

sum=$(md5sum "$user" | cut -d' ' -f1)
for s in "${SHIPPED[@]}"; do
  if [[ $sum == "$s" ]]; then
    cp "$shipped" "$user"
    echo "Updated $user"
    exit 0
  fi
done

echo ""
echo "$user has your own edits, so it was left alone."
echo "Its selection highlight may be invisible on most themes. To take"
echo "hyprsimple's current version, keeping a backup of yours:"
echo ""
echo "    hyprsimple-refresh-config.sh rofi/theme-picker/style.rasi"
echo ""
