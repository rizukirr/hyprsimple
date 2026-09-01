echo "Point the rofi configs at hyprsimple's defaults through an import"

# The rofi defaults moved into the install, and what lives in ~/.config/rofi is
# now a stub that imports them. That is what lets a rofi change reach an
# existing install through hyprsimple-update, instead of needing a migration
# like this one every time.
#
# A user's file is replaced only when it is byte-identical to something this
# project shipped, which is what proves it was never edited. Anything else is
# left alone and the command to convert it is printed instead.
#
# launcher/ and powermenu/ are deliberately absent: install.sh symlinks both
# into the active theme and theme-switcher.sh rewrites their style.rasi on
# every switch, so they are theme-owned rather than user config.

ROFI="$HOME/.config/rofi"
[[ -d $ROFI ]] || exit 0
[[ -d $HYPRSIMPLE_PATH/default/rofi ]] || exit 0

# Every version of each file this project has ever shipped, from git history.
CONFIG_SUMS=(
  5e2724e1ade07f5a75430e622c5f5908
  6eda1bc7e6de85d44aa9e38ea8b152aa
  7b85590ccab579c65be305991f02804c
  ca6b744537fcc93c7568810f5512798f
)
CONFIRM_SUMS=(59e1193374894b9d105a7a73461a3463)
FONT_SUMS=(ce6f90dc4a4cda09198cf4555a95a768)
KEYBINDINGS_SUMS=(b6504c1ac9cf0e6c5ca138d7a31961d7)
PICKER_SUMS=(
  c7933f90c1015e0c62229280ae097e8f
  de09d1f4884a513495491a85db8e639b
  e46ef3f79a8f839130a185fc8b45928d
)

# Idempotent: relinking to the same target on a re-run is a no-op. This runs
# before the file loop, so a stub is never left pointing at a link that does
# not exist yet.
ln -sfn "$HYPRSIMPLE_PATH/default/rofi" "$ROFI/hyprsimple"

matches() {
  local sum="$1"
  shift
  local s
  for s in "$@"; do
    [[ $sum == "$s" ]] && return 0
  done
  return 1
}

stub_if_pristine() {
  local rel="$1"
  shift
  local user="$ROFI/$rel"
  local stub="$HYPRSIMPLE_PATH/.config/rofi/$rel"

  [[ -f $user && -f $stub ]] || return 0
  # Already converted. This is what makes a re-run a no-op.
  cmp -s "$user" "$stub" && return 0

  if matches "$(md5sum "$user" | cut -d' ' -f1)" "$@"; then
    cp "$stub" "$user"
    echo "Updated $user"
  else
    echo ""
    echo "$user has your own edits, so it was left alone."
    echo "It will not receive hyprsimple's rofi updates until you convert it."
    echo "To take the import stub, keeping a backup of yours:"
    echo ""
    echo "    hyprsimple-refresh-config.sh rofi/$rel"
    echo ""
  fi
}

stub_if_pristine config.rasi "${CONFIG_SUMS[@]}"
stub_if_pristine confirm.rasi "${CONFIRM_SUMS[@]}"
stub_if_pristine font.rasi "${FONT_SUMS[@]}"
stub_if_pristine keybindings/style.rasi "${KEYBINDINGS_SUMS[@]}"
stub_if_pristine theme-picker/style.rasi "${PICKER_SUMS[@]}"
