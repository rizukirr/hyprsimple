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

  got=$(md5sum "$file" | cut -d' ' -f1)
  if [[ $got != "$want" ]]; then
    kept+=("$rel")
    continue
  fi

  # Never edited, so replacing it loses nothing.
  if [[ -f "$HYPRSIMPLE_PATH/.config/hypr/$rel" ]]; then
    cp -f "$HYPRSIMPLE_PATH/.config/hypr/$rel" "$file"
    echo "  Reset to the new placeholder: $rel"
  else
    rm -f "$file"
    echo "  Removed, now provided by the install: $rel"
  fi
done

if ((${#kept[@]} > 0)); then
  echo ""
  echo "  Left your edited files alone. They still load and still override:"
  for rel in "${kept[@]}"; do
    echo "    ~/.config/hypr/$rel"
  done
  echo "  To adopt the new defaults for one of them, empty it out and keep only"
  echo "  the settings you actually changed."
fi
