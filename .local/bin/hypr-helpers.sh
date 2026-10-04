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
# hyprpaper.conf is written by the caller first. It is what hyprpaper reads when
# it starts, at the next login or in the restart below.
#
# A restart used to be the only way this was done, and it was slow for a reason
# that has nothing to do with the image: hyprpaper takes about two seconds to
# stop when asked, and the screen has no wallpaper for all of them. Measured on
# one machine, 1.9s of a 2.2s theme switch.
#
# One image is set over hyprpaper's ipc, which took 6ms and leaves no gap.
#
# A folder cannot be. hyprpaper's ipc takes it without a word of complaint and
# then fails to load it as an image, which left the screen with no wallpaper at
# all. Cycling through a folder is something only its config can ask for, so
# hyprpaper is started again, but stopped at once rather than asked: it holds
# nothing worth saving. That took 0.01s, with the wallpaper gone for about a
# tenth of a second.
#
# The image given is the file itself, never ~/.cache/current_wallpaper. That
# file keeps its name when its content changes, and hyprpaper asked to show a
# path it is already showing has no reason to read it again.
show_wallpaper() {
  local path="$1" answer
  if [[ -f $path ]] &&
    answer=$(hyprctl hyprpaper wallpaper ",$path,cover" 2>/dev/null) && [[ -z $answer ]]; then
    return 0
  fi
  restart_hyprpaper
}

# Start hyprpaper again on its config, without the two seconds it takes to stop
# when asked.
#
# reset-failed is not tidying. systemd counts a unit killed this way as failed,
# and refuses to start one that failed five times in ten seconds. Switching
# theme a few times in a row reached that, and hyprpaper stayed down with no
# wallpaper until it was reset by hand. Clearing the count each time means a
# start asked for here is never refused for the stops done here.
restart_hyprpaper() {
  systemctl --user kill --signal=SIGKILL hyprpaper.service 2>/dev/null
  systemctl --user reset-failed hyprpaper.service 2>/dev/null
  systemctl --user restart hyprpaper.service
}
