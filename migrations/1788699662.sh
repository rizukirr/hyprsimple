echo "Say in your keybind file that a bind wants a description"

# applications.lua showed { description = ... } in both of its examples and
# never said what it is for. The key works without one, so it is easy to skip,
# and SUPER + / reads its list from Hyprland rather than from the file: a bind
# with no description had nothing to show there but the key itself, and until
# the change this migration accompanies it was left out of the list entirely.
#
# This is a comment change and nothing else. No binding is altered.
#
# The file is yours, so it is replaced only where it is still byte-identical to
# the version hyprsimple shipped before this change. Anything you have edited,
# which for this file is the likely case, is left exactly as it is and named at
# the end.

REL="hypr/bindings/applications.lua"
SHIPPED_SUM="f36b11db5b69aedd332bb4131b572281"

user="$HOME/.config/$REL"
shipped="$HYPRSIMPLE_PATH/.config/$REL"

if [[ ! -f $user || ! -f $shipped ]]; then
  echo "  Nothing to do."
  exit 0
fi

if cmp -s "$user" "$shipped"; then
  exit 0
fi

if [[ $(md5sum "$user" | cut -d' ' -f1) == "$SHIPPED_SUM" ]]; then
  cp -f "$shipped" "$user"
  echo "  Added the note to $user."
else
  echo "  Left $user alone, because you have your own version."
  echo "  The note it would have added:"
  echo "    Give every bind a description, or it has nothing to show in SUPER + /"
  echo "  To take hyprsimple's version and lose your edits:"
  echo "    hyprsimple-refresh-config.sh $REL"
fi
