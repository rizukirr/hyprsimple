echo "Remove the battery monitor's broken autostart link"

# The repository committed systemd's enable state, not just its units, and two
# of those symlinks had another user's home path baked into them:
#
#   default.target.wants/battery-monitor.service -> /home/rizki/...
#   timers.target.wants/battery-monitor.timer    -> /home/rizki/...
#
# install.sh runs `systemctl --user enable --now battery-monitor.timer`, which
# rewrote the timer one, so it points where it should. Nothing ever enabled the
# service, so its link is still broken on every install.
#
# It is not inert. systemd resolves a .wants symlink by its filename rather than
# its target, so default.target pulls in battery-monitor.service anyway and the
# check runs once at login on top of the timer that already runs it every 30
# seconds. The timer is the only thing that was meant to start it.
#
# Only a link that does not resolve is removed. One that does was enabled by
# someone on purpose, and this leaves it alone.

LINK="$HOME/.config/systemd/user/default.target.wants/battery-monitor.service"

[[ -L $LINK ]] || exit 0
[[ -e $LINK ]] && exit 0

target=$(readlink "$LINK")
case "$target" in
  "$HOME"/*) exit 0 ;;
esac

rm -f "$LINK"
echo "  Removed $LINK"
echo "  It pointed at $target, which does not exist here."

if command -v systemctl >/dev/null 2>&1; then
  systemctl --user daemon-reload 2>/dev/null || true
fi

echo "  The battery monitor still runs, on its timer, every 30 seconds."
