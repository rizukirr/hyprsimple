echo "Move hyprsimple's own Hyprland config into the install"

# The project's lua config now lives in ~/.local/share/hyprsimple/default/hypr
# and is loaded before your ~/.config/hypr files, which still override it. That
# means future fixes reach you through hyprsimple-update with no migration.
#
# A file here is only replaced when it is byte-identical to something hyprsimple
# shipped, which proves it was never edited. Anything else is left exactly as it
# is: it still loads, it still wins, and nothing changes for you.

CONF="$HOME/.config/hypr"
[[ -d $CONF ]] || exit 0

# path:md5 of every default hyprsimple has shipped for these files
SHIPPED=(
  "looknfeel.lua:3aeae1b3e36d5f13dee3ecc71b8fe810"
  "windows.lua:e2a14c4c54c95852c3b7f0cf2f5ce427"
  "input.lua:02d9967977f6257077b2fd85a86a5d19"
  "autostart.lua:d46075110f45ce72a8cb8f028456cc41"
  "bindings.lua:84eed4e973a516aec8eeaa78f434cab1"
  "bindings/media.lua:89d27d893910185599f699b75b96f7da"
  "bindings/recording.lua:e9b1d4a05cbe57546bd5fbc7c5ccb56e"
  "bindings/screenshot.lua:b99fae81ccd7ceb81800e595540223a4"
  "bindings/system.lua:e5514b369a1be906409997b343c10f07"
  "bindings/window-management.lua:c803224f01e182159b043bba64af541d"
  "bindings/workspaces.lua:25a2f968e91a3b194c045bfe9de6a4c7"
  "vars.lua:474cead79fc88010f0073135d5199bad"
)

kept=()

for entry in "${SHIPPED[@]}"; do
  rel="${entry%%:*}"
  want="${entry##*:}"
  file="$CONF/$rel"

  [[ -f $file ]] || continue

  placeholder="$HYPRSIMPLE_PATH/.config/hypr/$rel"
  got=$(md5sum "$file" | cut -d' ' -f1)

  # Already migrated: the file is byte-identical to the placeholder we ship.
  # This is what makes a second run a no-op.
  if [[ -f $placeholder ]] && cmp -s "$file" "$placeholder"; then
    continue
  fi

  if [[ $got != "$want" ]]; then
    # Customised. Move it aside rather than leaving it loaded: window rules,
    # animations, curves, layer rules and binds are additive, so keeping this
    # file alongside the new default would register everything twice.
    saved="$file.pre-split.$(date +%s)"
    mv "$file" "$saved"
    kept+=("$rel -> $saved")
  fi

  if [[ -f $placeholder ]]; then
    cp -f "$placeholder" "$file"
    echo "  Now provided by the install, placeholder written: $rel"
  else
    rm -f "$file"
    echo "  Now provided by the install, removed: $rel"
  fi
done

if ((${#kept[@]} > 0)); then
  echo ""
  echo "  You had edited these. Your versions are saved, not deleted:"
  for entry in "${kept[@]}"; do
    echo "    ${entry}"
  done
  echo ""
  echo "  hyprsimple's defaults now apply. To restore one of your settings, copy"
  echo "  just that setting from the saved file into the placeholder beside it."
  echo "  Do not restore the whole file: it would duplicate every window rule and"
  echo "  animation the defaults already provide."
fi
