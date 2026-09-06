local vars = require("default.hypr.vars")

hl.on("hyprland.start", function()
  hl.exec_cmd("uwsm app -- dunst")
  hl.exec_cmd("uwsm app -- waybar")
  hl.exec_cmd("uwsm app -- wl-paste --type text --watch cliphist store")
  hl.exec_cmd("uwsm app -- wl-paste --type image --watch cliphist store")
  hl.exec_cmd("uwsm app -- hypridle")
  -- hyprsunset applies the profiles in ~/.config/hypr/hyprsunset.conf. Nothing
  -- started it before, so those profiles never ran: the file invited you to
  -- uncomment a night profile and uncommenting it did nothing. SUPER+N starts
  -- it too, but only for that session and only once pressed.
  hl.exec_cmd("uwsm app -- hyprsunset")
  hl.exec_cmd("uwsm app -- " .. os.getenv("HOME") .. "/.local/bin/capslock-notify.sh")
  hl.exec_cmd("uwsm app -- " .. vars.terminal)
  -- apply, not on: the flag records what you chose, and login restores it
  -- rather than overriding it.
  hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/live-wallpaper-toggle.sh apply")

  -- Slow-app-launch fix: import env into systemd + dbus
  hl.exec_cmd([[sh -c 'systemctl --user import-environment $(env | cut -d= -f1)']])
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")
end)

-- Mirror the laptop screen onto an external display as soon as one appears,
-- so plugging into a projector shows the same picture without a keypress.
-- SUPER + SHIFT + M switches to extended afterwards.
--
-- monitor-mirror-toggle.sh has documented this handler as its caller since the
-- day its on|off|quiet modes were added, and the handler was never written, so
-- those modes had no caller at all and a hotplug did nothing.
--
-- The event's payload is not read. The script asks hyprctl which monitors are
-- there, which is one source of truth rather than two, and it exits quietly
-- when there is no external display. That matters because this also fires for
-- the built-in panel at startup.
hl.on("monitor.added", function()
  hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/monitor-mirror-toggle.sh on quiet")
end)
