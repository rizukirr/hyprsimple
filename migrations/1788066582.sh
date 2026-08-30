echo "Move hyprsimple's dunst default into the install"

# hyprsimple's dunst settings now live in ~/.local/share/hyprsimple, symlinked
# in as dunstrc.d/10-hyprsimple.conf, so future changes reach you through
# hyprsimple-update with no migration. Your ~/.config/dunst/dunstrc becomes a
# short pointer file, and dunstrc.d/99-user.conf is yours to edit.
#
# Your dunstrc is only replaced when it is byte-identical to something
# hyprsimple shipped, which proves it was never edited. Anything else is kept
# at dunstrc.pre-split.<timestamp>, and the lines that differed are copied into
# 99-user.conf as comments so you can uncomment what you want back.

DUNST_DIR="$HOME/.config/dunst"
DUNSTRC="$DUNST_DIR/dunstrc"
BASE="$HYPRSIMPLE_PATH/.config/dunst/dunstrc"
DEFAULT="$HYPRSIMPLE_PATH/default/dunst/10-hyprsimple.conf"

[[ -f $BASE && -f $DEFAULT ]] || exit 0

mkdir -p "$DUNST_DIR/dunstrc.d"
ln -sfn "$DEFAULT" "$DUNST_DIR/dunstrc.d/10-hyprsimple.conf"

# md5 of every dunstrc hyprsimple has shipped
SHIPPED=(
  "9074d302ad96206fc1d3e32976b7b53f"
)

if [[ -f $DUNSTRC ]] && ! cmp -s "$DUNSTRC" "$BASE"; then
  sum=$(md5sum "$DUNSTRC" | cut -d' ' -f1)
  matched=""
  for s in "${SHIPPED[@]}"; do
    [[ $sum == "$s" ]] && matched=yes
  done

  if [[ -n $matched ]]; then
    cp "$BASE" "$DUNSTRC"
  else
    kept="$DUNSTRC.pre-split.$(date +%s)"
    mv "$DUNSTRC" "$kept"
    cp "$BASE" "$DUNSTRC"

    # The differing lines go in as comments. Inert text cannot land a setting in
    # the wrong section, which parsing them into live config could.
    user="$DUNST_DIR/dunstrc.d/99-user.conf"
    {
      echo "# hyprsimple moved its dunst defaults to dunstrc.d/10-hyprsimple.conf."
      echo "# Your previous dunstrc is saved at $kept"
      echo "#"
      echo "# These lines differed from the default hyprsimple shipped."
      echo "# Uncomment any you want to keep:"
      echo "#"
      diff "$DEFAULT" "$kept" | sed -n 's/^> /#     /p'
    } >>"$user"

    # The earlier migration already saved this file as it was before anything
    # touched it, which is a more complete record than the copy just made.
    # Promote it into this name so the user is left with one file, not two.
    bak=$(ls -1 "$DUNSTRC".bak.* 2>/dev/null | tail -1)
    [[ -n $bak ]] && mv -f "$bak" "$kept"

    echo "Kept your dunstrc at $kept"
    echo "Its differences are listed, commented out, in $user"
  fi
fi

# Create the stub only when there is nothing there. Never overwrite it.
[[ -e "$DUNST_DIR/dunstrc.d/99-user.conf" ]] || cat >"$DUNST_DIR/dunstrc.d/99-user.conf" <<'STUB'
# Your dunst settings. This file is the last drop-in in lexical order, so
# anything here overrides both hyprsimple's defaults and the theme colours.
# hyprsimple never writes to this file.
STUB

if pgrep -x dunst >/dev/null; then
  pkill dunst
  uwsm app -- dunst &
fi
