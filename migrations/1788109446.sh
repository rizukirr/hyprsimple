echo "Remove wallpaper selection from the app launcher"

# Wallpaper selection was reachable twice: from SUPER + SHIFT + W, which now
# opens a grid of previews, and as a rofi mode inside the app launcher, which
# was a list of filenames. Theme selection was removed from the launcher for
# the same reason in #31. The script behind the mode has no caller left.
#
# A file is replaced here only when it is byte-identical to something
# hyprsimple shipped, which proves it was never edited. Anything else is left
# alone and the command to update it is printed instead.

ROFI="$HOME/.config/rofi"
[[ -d $ROFI ]] || exit 0

LAUNCHER_SUMS=(
  "88f5b17976a2339d0342ff1885123aae"
  "ca6b744537fcc93c7568810f5512798f"
  "eb94c293393c1657cf5667790b412aca"
  "f2d7e3ca2f9f2c907383754ad2d3b345"
)
ROOT_SUMS=(
  "6eda1bc7e6de85d44aa9e38ea8b152aa"
  "7b85590ccab579c65be305991f02804c"
  "ca6b744537fcc93c7568810f5512798f"
)
SELECTOR_SUMS=(
  "642a15c7b3c065fb6c07612a519def00"
  "940385c9c18dce48b8becac8a8777fbe"
)

matches() {
  local sum="$1"
  shift
  local s
  for s in "$@"; do
    [[ $sum == "$s" ]] && return 0
  done
  return 1
}

replace_if_pristine() {
  local rel="$1"
  shift
  local user="$ROFI/$rel"
  local shipped="$HYPRSIMPLE_PATH/.config/rofi/$rel"

  [[ -f $user && -f $shipped ]] || return 0
  cmp -s "$user" "$shipped" && return 0

  if matches "$(md5sum "$user" | cut -d' ' -f1)" "$@"; then
    cp "$shipped" "$user"
    echo "Updated $user"
  else
    echo ""
    echo "$user has your own edits, so it was left alone."
    echo "It still offers wallpaper selection inside the app launcher. To take"
    echo "hyprsimple's current version, keeping a backup of yours:"
    echo ""
    echo "    hyprsimple-refresh-config.sh rofi/$rel"
    echo ""
  fi
}

replace_if_pristine launcher/config.rasi "${LAUNCHER_SUMS[@]}"
replace_if_pristine config.rasi "${ROOT_SUMS[@]}"

# The script behind the retired mode. Removed only when untouched.
selector="$ROFI/scripts/wallpaper-selector.sh"
if [[ -f $selector ]] && matches "$(md5sum "$selector" | cut -d' ' -f1)" "${SELECTOR_SUMS[@]}"; then
  rm -f "$selector"
  rmdir "$ROFI/scripts" 2>/dev/null
  echo "Removed $selector, which no longer has a caller"
fi
