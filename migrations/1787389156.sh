echo "Repair hyprpaper.conf wallpaper paths pointing at another user's home"

# .config/hypr/hyprpaper.conf shipped with a hardcoded /home/rizki/... path, so a
# fresh install left every user whose name is not "rizki" with a broken wallpaper
# path until their first theme switch rewrote the file.

CONF="$HOME/.config/hypr/hyprpaper.conf"
[[ -f $CONF ]] || exit 0

# Rewrite any /home/<someone-else>/ prefix to this user's home. Anchored to the
# start of the path so it cannot touch anything else, and a no-op once correct.
if grep -qE "^\s*path\s*=\s*/home/[^/]+/" "$CONF" &&
   ! grep -qE "^\s*path\s*=\s*${HOME}/" "$CONF"; then
  sed -i -E "s#^(\s*path\s*=\s*)/home/[^/]+/#\1${HOME}/#" "$CONF"
  echo "  Rewrote wallpaper path to $HOME"

  if systemctl --user is-active hyprpaper.service &>/dev/null; then
    systemctl --user restart hyprpaper.service
  fi
fi
