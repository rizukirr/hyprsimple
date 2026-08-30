echo "Move theme selection out of the app launcher and into the picker"

# Theme selection was reachable twice: from its own binding and as a rofi mode
# inside the app launcher. The launcher no longer offers it, and the script
# behind that mode has no caller.
#
# A file is replaced here only when it is byte-identical to something
# hyprsimple shipped, which proves it was never edited. Anything else is left
# alone and the command to update it is printed instead.

ROFI="$HOME/.config/rofi"
[[ -d $ROFI ]] || exit 0

LAUNCHER_SUMS=(
  88f5b17976a2339d0342ff1885123aae
  ca6b744537fcc93c7568810f5512798f
  eb94c293393c1657cf5667790b412aca
  f2d7e3ca2f9f2c907383754ad2d3b345
)
ROOT_SUMS=(
  6eda1bc7e6de85d44aa9e38ea8b152aa
  7b85590ccab579c65be305991f02804c
  ca6b744537fcc93c7568810f5512798f
)
SELECTOR_SUMS=(
  026b53f5a56c71270ae269ddb2b93141
  0eecd036a2cbfa808227cb01b7096fbc
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
    echo "It still offers theme selection inside the app launcher. To take"
    echo "hyprsimple's current version, keeping a backup of yours:"
    echo ""
    echo "    hyprsimple-refresh-config.sh rofi/$rel"
    echo ""
  fi
}

# The picker's own rofi theme is a new file, so there is nothing to gate on. It
# is installed unconditionally when absent. Without it rofi still opens, but
# with default styling and no grid, which is not the feature.
if [[ -d $HYPRSIMPLE_PATH/.config/rofi/theme-picker ]]; then
  mkdir -p "$ROFI/theme-picker"
  for f in "$HYPRSIMPLE_PATH/.config/rofi/theme-picker/"*; do
    [[ -f $f ]] || continue
    target="$ROFI/theme-picker/$(basename "$f")"
    if [[ ! -e $target ]]; then
      cp "$f" "$target"
      echo "Installed $target"
    fi
  done
fi

replace_if_pristine launcher/config.rasi "${LAUNCHER_SUMS[@]}"
replace_if_pristine config.rasi "${ROOT_SUMS[@]}"

# The script behind the retired launcher mode. Removed only when untouched.
selector="$ROFI/scripts/theme-selector.sh"
if [[ -f $selector ]] && matches "$(md5sum "$selector" | cut -d' ' -f1)" "${SELECTOR_SUMS[@]}"; then
  rm -f "$selector"
  echo "Removed $selector, which no longer has a caller"
fi
