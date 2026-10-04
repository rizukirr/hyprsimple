echo "Replace waybar with the Quickshell bar"

# hyprsimple's bar is now a Quickshell config, shipped in default/quickshell
# and started at login by autostart.lua. An install from before that still has
# waybar running in this session and nothing that would start the new bar
# until the next login.
#
# The update installs quickshell and its icon font from packages.txt before
# migrations run, so by here the bar can start. This stops waybar, starts the
# bar when there is a session to start it in, and removes the waybar package.
#
# ~/.config/waybar is yours and is left where it is. Nothing reads it any more.

if pgrep -x waybar >/dev/null; then
  pkill -x waybar
fi

RESTART="$HOME/.local/bin/hyprsimple-restart-bar.sh"
if [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]] && command -v qs >/dev/null 2>&1 && [[ -x $RESTART ]]; then
  "$RESTART"
  echo "Started the bar."
else
  echo "No Hyprland session here, so the bar starts at the next login."
fi

# Asked for only when there is something to remove, so a machine without
# waybar never reaches sudo. A removal that fails is reported and does not stop
# the update: a leftover package is harmless, and failing here would run the
# two steps above again on every update for no gain.
if pacman -Qi waybar >/dev/null 2>&1; then
  if sudo pacman -Rns --noconfirm waybar >/dev/null 2>&1; then
    echo "Removed the waybar package."
  else
    echo "Could not remove the waybar package. Remove it with: sudo pacman -Rns waybar"
  fi
fi

exit 0
