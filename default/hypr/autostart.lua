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
