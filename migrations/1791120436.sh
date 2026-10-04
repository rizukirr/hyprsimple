echo "Clear away the screenshot menu, now that Print takes the picture itself"

# Print used to open a menu that asked what to capture and where to put it.
# It goes straight to a picker now, drag for a region or click for a window,
# and the script that opened the menu, hyprsimple-screenshot-menu.sh, is no
# longer shipped.
#
# Two things an update cannot reach on its own:
#
# The update copies scripts into ~/.local/bin and never removes one, so the
# old script stays behind. It would still run, and open a panel the bar no
# longer has, which is a key that does nothing with no word of why.
#
# And a binding of your own may call it. The shipped binding is in a file the
# install owns and arrives with the update, but a line you added to a file
# under ~/.config/hypr is yours and is never rewritten. Left alone it would
# call a script that is gone.

STALE="$HOME/.local/bin/hyprsimple-screenshot-menu.sh"
CONFIG_DIR="$HOME/.config/hypr"

# A binding of the user's own that calls the old script is pointed at the
# picker. Only that one name is replaced, in lua files, each backed up once
# beside itself first. Everything else in the file is left exactly as it was.
rewritten=0
if [[ -d $CONFIG_DIR ]]; then
  while IFS= read -r file; do
    [[ -e $file.bak ]] || cp -p "$file" "$file.bak"
    sed -i 's|hyprsimple-screenshot-menu\.sh|screenshot.sh smart|g' "$file"
    echo "  $file now calls screenshot.sh smart. The file as it was is in $file.bak"
    rewritten=$((rewritten + 1))
  done < <(grep -rlF --include='*.lua' 'hyprsimple-screenshot-menu.sh' "$CONFIG_DIR" 2>/dev/null)
fi

if [[ -e $STALE ]]; then
  rm -f "$STALE"
  echo "  Removed $STALE"
elif ((rewritten == 0)); then
  echo "  Nothing to clear away."
fi

exit 0
