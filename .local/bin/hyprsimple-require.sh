#!/bin/bash

# Source a hyprsimple helper, or stop rather than carry on without it.
#
# `source` on a file that is not there prints one line and returns non-zero,
# and none of these scripts set -e, so every one of them continued into code
# whose functions no longer existed. bash reports each missing function on
# stderr and keeps going, so the script ran to the end and announced success.
#
# Measured with hyprsimple-theme-deliver.sh removed, which is the state of any
# install whose ~/.local/bin predates the file:
#
#   theme-switcher.sh deep-sea
#     -> "deliver_theme_configs: command not found", exit 0,
#        "Theme 'deep-sea' applied!", and none of the eight generated files
#        delivered.
#
# and with hypr-helpers.sh removed:
#
#   wallpaper-switcher.sh next
#     -> "write_hyprpaper_conf: command not found", exit 0,
#        "Wallpaper 2-deep-sea.jpg", and hyprpaper.conf never written, so the
#        wallpaper on screen did not change.
#
# hyprsimple-update.sh already tests for its one helper before sourcing it, for
# the same reason. This is that check, in one place, for the callers that were
# still sourcing blind.
#
# Usage: require_helper <name.sh> [<name.sh> ...]
# Sourced, not run, so the definitions land in the caller's shell.

require_helper() {
  local name path missing=()
  for name in "$@"; do
    path="$HOME/.local/bin/$name"
    if [[ -r $path ]]; then
      # shellcheck source=/dev/null
      source "$path"
    else
      missing+=("$name")
    fi
  done

  (( ${#missing[@]} == 0 )) && return 0

  local list="${missing[*]}"
  echo "hyprsimple: missing helper(s): $list" >&2
  echo "Run hyprsimple-update to restore them." >&2
  # Told on screen as well. These scripts are run from a keybind, where stderr
  # goes nowhere anyone will see, and the whole point is that the failure used
  # to be announced as success.
  command -v notify-send >/dev/null &&
    notify-send -u critical "hyprsimple" "Missing helper: $list. Run hyprsimple-update." 
  exit 1
}
