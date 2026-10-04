#!/bin/bash

# Shared helpers for hyprpaper management

write_hyprpaper_conf() {
  local wp_path="$1"
  local timeout="$2"
  local conf="$HOME/.config/hypr/hyprpaper.conf"
  if [[ -n "$timeout" ]]; then
    cat > "$conf" <<EOF
wallpaper {
    monitor =
    path = $wp_path
    fit_mode = cover
    timeout = $timeout
}

splash = false
ipc = true
EOF
  else
    cat > "$conf" <<EOF
wallpaper {
    monitor =
    path = $wp_path
    fit_mode = cover
}

splash = false
ipc = true
EOF
  fi
}

# Show a wallpaper now: one image, or a folder of them to cycle through.
#
# hyprpaper is asked over its ipc, and only restarted when it does not answer.
# A restart was the only way this was done, and it is slow for a reason that
# has nothing to do with the image: hyprpaper takes about two seconds to stop.
# Measured on one machine, a theme switch took 2.2s of which the restart was
# 1.9s, and the same wallpaper set over ipc took 6ms.
#
# hyprpaper.conf is still written by the caller. It is what a hyprpaper started
# later reads, at the next login or after the restart below.
#
# The path given is the image or folder itself, never ~/.cache/current_wallpaper.
# That file keeps its name when its content changes, and hyprpaper asked to
# show a path it is already showing has no reason to read it again.
show_wallpaper() {
  local path="$1" answer
  if answer=$(hyprctl hyprpaper wallpaper ",$path,cover" 2>/dev/null) && [[ -z $answer ]]; then
    return 0
  fi
  systemctl --user restart hyprpaper.service
}
