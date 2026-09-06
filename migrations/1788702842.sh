echo "Hold the battery monitor until there is a session to notify"

# battery-monitor.timer was WantedBy=timers.target, so it started with the user
# manager, before any compositor. battery-monitor.service said
# After=graphical-session.target, which is ordering only and does nothing when
# that target is not part of the same job.
#
# Measured on a login: the service ran at 11:54:23 and Hyprland was selected in
# the same second, after it. With a low battery that means battery-monitor.sh
# dims the panel to 5% at the greeter, and its notify-send activates dunst over
# D-Bus into a session with no Wayland display, where dunst aborts on
# "Couldn't initialize X11 output", is retried five times and burns its start
# limit. The notification is lost and dunst.service is left failed.
#
# Both units now belong to graphical-session.target, so the timer exists only
# while a session does.
#
# The files are yours, so each is replaced only where it is still
# byte-identical to the version shipped before this change. The enablement is
# moved only when the timer is enabled, because that is the half that decides
# when it runs.

TIMER_SUM="891c046d10b45a0bff7c6e5f92cfcc9d"
SERVICE_SUM="6d030dde190c60a091b60d2b2604254d"

replaced=0
skipped=()

replace_unit() {
  local name="$1" sum="$2"
  local user="$HOME/.config/systemd/user/$name"
  local shipped="$HYPRSIMPLE_PATH/.config/systemd/user/$name"

  [[ -f $user && -f $shipped ]] || return 0
  cmp -s "$user" "$shipped" && return 0

  if [[ $(md5sum "$user" | cut -d' ' -f1) == "$sum" ]]; then
    cp -f "$shipped" "$user"
    replaced=$((replaced + 1))
  else
    skipped+=("$name")
  fi
}

replace_unit battery-monitor.timer "$TIMER_SUM"
replace_unit battery-monitor.service "$SERVICE_SUM"

if (( replaced == 0 )); then
  if (( ${#skipped[@]} > 0 )); then
    echo "  Left alone, because you have your own version:"
    printf '    %s\n' "${skipped[@]}"
    echo "  Yours will keep running the battery monitor before the session starts."
    echo "  To take hyprsimple's and lose your edits:"
    echo "    hyprsimple-refresh-config.sh systemd/user/battery-monitor.timer"
    echo "    hyprsimple-refresh-config.sh systemd/user/battery-monitor.service"
  fi
  exit 0
fi

systemctl --user daemon-reload 2>/dev/null || true

# The unit moved from timers.target to graphical-session.target, and the
# enabling symlink does not move on its own. Only touched when the timer was
# already enabled, so a machine that had deliberately turned it off stays off.
if systemctl --user is-enabled battery-monitor.timer &>/dev/null; then
  systemctl --user disable battery-monitor.timer &>/dev/null || true
  systemctl --user enable battery-monitor.timer &>/dev/null || true
  # Started here only if a session is already up, which is the case when this
  # runs from hyprsimple-update inside one. Otherwise the next login starts it.
  if systemctl --user is-active graphical-session.target &>/dev/null; then
    systemctl --user restart battery-monitor.timer &>/dev/null || true
  fi
  echo "  The battery monitor now starts with your session rather than before it."
else
  echo "  Updated the units. The timer is not enabled here, so nothing was started."
fi

if (( ${#skipped[@]} > 0 )); then
  echo "  Left alone, because you have your own version:"
  printf '    %s\n' "${skipped[@]}"
fi
