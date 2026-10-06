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
#
# A folder holding one image is shown as that image. There is nothing in it to
# cycle through, and the restart is not the 0.01s it was once measured at: on a
# hyprpaper that has been up for more than a few seconds it took 1.8s, which is
# how long a theme switch then waited for its wallpaper.
show_wallpaper() {
  local path="$1" answer images=()
  if [[ -d $path ]]; then
    mapfile -t images < <(wallpaper_images "$path")
    if (( ${#images[@]} == 1 )) && ! hyprpaper_cycling; then
      path="${images[0]}"
    fi
  fi
  if [[ -f $path ]] &&
    answer=$(hyprctl hyprpaper wallpaper ",$path,cover" 2>/dev/null) && [[ -z $answer ]]; then
    return 0
  fi
  restart_hyprpaper
}

# The images directly inside a folder, one per line, in the order hyprpaper
# cycles through them. Globbed rather than found, so it needs nothing but bash.
wallpaper_images() (
  shopt -s nullglob nocaseglob
  for image in "$1"/*.jpg "$1"/*.jpeg "$1"/*.png "$1"/*.webp; do
    [[ -f $image ]] && printf '%s\n' "$image"
  done
)

# Whether hyprpaper is cycling through a folder of several images now, judged
# by the folder the image on screen came from.
#
# An image set over ipc does not stop that, so the next one in the old folder
# would replace it. A hyprpaper that cannot be asked counts as cycling, which
# sends the caller to a restart, the one thing that also starts it.
hyprpaper_cycling() {
  local active line shown=() folder
  active=$(hyprctl hyprpaper listactive 2>/dev/null) || return 0
  while IFS= read -r line; do
    [[ $line == *": "* ]] || continue
    folder="${line#*: }"
    folder="${folder%/*}"
    mapfile -t shown < <(wallpaper_images "$folder")
    (( ${#shown[@]} > 1 )) && return 0
  done <<<"$active"
  return 1
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
