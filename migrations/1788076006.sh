echo "Move hyprsimple's hyprlock, hypridle and xdph defaults into the install"

# These three configs now live in ~/.local/share/hyprsimple and are reached
# through ~/.config/hypr/hyprsimple, a symlink this migration creates. Your own
# files become short lists of source lines with room for your overrides, so
# future changes reach you through hyprsimple-update with no migration.
#
# A file is only replaced when it is byte-identical to something hyprsimple
# shipped, which proves it was never edited. Anything else is kept at
# <name>.pre-split.<timestamp> and its differences are listed, commented out,
# in the file that replaces it.

CONF="$HOME/.config/hypr"
DEFAULTS="$HYPRSIMPLE_PATH/default/hypr"
LINK="$CONF/hyprsimple"

[[ -d $CONF && -d $DEFAULTS ]] || exit 0

ln -sfn "$DEFAULTS" "$LINK"

# A missing source is not fatal in hyprlang: hypridle would start with no rules
# at all, so the machine would never lock, blank or suspend, and the only sign
# would be a line in a log. Nothing below runs unless the link resolves.
if [[ ! -e "$LINK/hypridle/10-general.conf" ]]; then
  echo "$LINK does not resolve to the hyprsimple defaults. Nothing was changed." >&2
  exit 1
fi

# name:md5 of every version hyprsimple has shipped for these files
SHIPPED=(
  "hypridle.conf:9baa82fba2dfa10704a985125ac9cbfe"
  "xdph.conf:78b554b8f101109f7105cd4a40b02de2"
  "hyprlock.conf:d924867c1f268c9520c2dca3b28fd639"
)

for name in hyprlock.conf hypridle.conf xdph.conf; do
  user="$CONF/$name"
  new="$HYPRSIMPLE_PATH/.config/hypr/$name"

  [[ -f $new ]] || continue

  # Already converted by an earlier run. Two shapes count as converted: the
  # file is byte-identical to what ships, or it is that file plus the comment
  # block the customized branch below appends. Testing only the first would
  # make a second run take the customized branch again and write a second
  # .pre-split.
  if [[ -f $user ]]; then
    if cmp -s "$user" "$new" || grep -q "^# Your previous $name is saved at " "$user"; then
      continue
    fi
  fi

  if [[ ! -f $user ]]; then
    cp "$new" "$user"
    continue
  fi

  sum=$(md5sum "$user" | cut -d' ' -f1)
  matched=""
  for entry in "${SHIPPED[@]}"; do
    [[ ${entry%%:*} == "$name" && ${entry##*:} == "$sum" ]] && matched=yes
  done

  if [[ -n $matched ]]; then
    cp "$new" "$user"
    echo "Converted $user"
  else
    kept="$user.pre-split.$(date +%s)"
    mv "$user" "$kept"
    cp "$new" "$user"

    # Differences go in as comments. Inert text cannot land a setting in a
    # category that ignores it, which pasting them in as config could.
    diffs=$(diff "$DEFAULTS/$name" "$kept" 2>/dev/null | sed -n 's/^> /#     /p')
    {
      echo ""
      echo "# Your previous $name is saved at $kept"
      if [[ -n $diffs ]]; then
        echo "# These lines differed from the default hyprsimple shipped."
        echo "# Uncomment any you want to keep:"
        echo "#"
        printf '%s\n' "$diffs"
      fi
    } >>"$user"

    echo "Kept your $name at $kept"
  fi
done
