echo "Replace waybar with the Quickshell bar"

# hyprsimple's bar is now a Quickshell config, shipped in default/quickshell
# and started at login by autostart.lua. An install from before that still has
# waybar running in this session and nothing that would start the new bar
# until the next login.
#
# The update installs quickshell and its icon font from packages.txt before
# migrations run. This stops waybar, starts the bar when there is a session to
# start it in, removes scripts that existed for waybar and for the rofi sound
# menu the bar replaces, and removes the waybar package.
#
# ~/.config/waybar is yours and is left where it is. Nothing reads it any more.

# Checked before anything is stopped or removed. The update carries on when a
# package fails to install, so quickshell can be missing here, and autostart
# already launches it instead of waybar. Taking waybar away as well would
# leave no bar now and none at the next login. Failing leaves waybar running
# and runs this again on the next update.
if ! command -v qs >/dev/null 2>&1; then
  echo "quickshell is not installed, so waybar is left as it is." >&2
  echo "Install it with: sudo pacman -S quickshell ttf-material-symbols-variable" >&2
  echo "Then run hyprsimple-migrate." >&2
  exit 1
fi

if pgrep -x waybar >/dev/null; then
  pkill -x waybar
fi

RESTART="$HOME/.local/bin/hyprsimple-restart-bar.sh"
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} && -x $RESTART ]]; then
  "$RESTART"
  echo "Started the bar."
else
  echo "No Hyprland session here, so the bar starts at the next login."
fi

# The update copies scripts into ~/.local/bin and never removes one, so these
# would stay behind with nothing left to call them.
#
# hyprsimple-restart-waybar.sh is not in the list. The update running this
# migration is the one from before the change, still being read from its old
# copy, and it calls that script after the migrations. Removing it here made
# that run end with "No such file or directory". Left in place it does nothing:
# it is called with --if-running and waybar is no longer running.
for stale in hyprsimple-refresh-waybar.sh \
  waybar-muslimtify.sh waybar-screenrecording.sh hyprsimple-audio-menu.sh; do
  rm -f "$HOME/.local/bin/$stale"
done

# Asked for only when there is something to remove, so a machine without
# waybar never reaches sudo. A removal that fails is reported and does not stop
# the update: a leftover package is harmless, and failing here would run the
# steps above again on every update for no gain.
if pacman -Qi waybar >/dev/null 2>&1; then
  if sudo pacman -Rns --noconfirm waybar >/dev/null 2>&1; then
    echo "Removed the waybar package."
  else
    echo "Could not remove the waybar package. Remove it with: sudo pacman -Rns waybar"
  fi
fi

exit 0
