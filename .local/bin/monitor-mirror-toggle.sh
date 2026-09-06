#!/bin/bash

# Toggle between extended and mirror mode
# Auto-detects primary (built-in) and external monitors
#
# Usage: monitor-mirror-toggle.sh [on|off|toggle] [quiet]
#   on     - force mirror mode
#   off    - force extended mode
#   toggle - flip current mode (default)
#   quiet  - say nothing, for a caller that is not a keypress
#
# "on quiet" is what the monitor.added handler in default/hypr/autostart.lua
# runs, so plugging in an external display (a projector) mirrors the laptop
# screen rather than extending onto it. SUPER + SHIFT + M flips it afterwards.
#
# That handler did not exist until now. This comment claimed it did from the
# moment on|off|quiet were added, and nothing called any of them, so the modes
# were unreachable and quiet was never exercised. It did not work either: it
# suppressed the two error notifications and neither of the success ones, so
# the one caller it was written for would have popped a notification on every
# hotplug.

MODE="${1:-toggle}"
QUIET="${2:-}"

# Every notification goes through here. Putting the check in the two error
# paths only was what left quiet half done.
notify() {
  [[ $QUIET == "quiet" ]] && return 0
  notify-send "$@"
}

case "$MODE" in
on | off | toggle) ;;
*)
  echo "Usage: $(basename "$0") [on|off|toggle]" >&2
  exit 2
  ;;
esac

PRIMARY=$(hyprctl monitors -j | jq -r '.[] | select(.name | test("^eDP")) | .name' | head -1)
EXTERNAL=$(hyprctl monitors -j | jq -r '.[] | select(.name | test("^eDP") | not) | .name' | head -1)

if [[ -z $EXTERNAL ]]; then
  notify "Monitor Mode" "No external monitor detected"
  exit 1
fi

if [[ -z $PRIMARY ]]; then
  notify "Monitor Mode" "No built-in (eDP) display detected"
  exit 1
fi

# Both of these used to be `hyprctl keyword monitor "..."`, and Hyprland refuses
# that outright when the config is lua rather than hyprlang:
#
#   $ hyprctl keyword monitor "HDMI-A-1,preferred,auto,1"
#   keyword can't work with non-legacy parsers. Use eval.
#
# hyprsimple's config has been lua since the config split, so both calls have
# always failed, and the notifications below announced a change that had not
# happened. SUPER + SHIFT + M has never mirrored anything on any install.
#
# hyprctl eval runs a lua string against the same config, and hl.monitor takes
# the mirror as a field. It answers "ok", so a failure is visible rather than
# assumed away.
apply_monitor() {
  local lua="$1" out
  out=$(hyprctl eval "$lua" 2>&1)
  if [[ $out != "ok" ]]; then
    echo "hyprctl rejected the monitor change: $out" >&2
    notify -u critical "Monitor Mode" "Hyprland rejected the change"
    return 1
  fi
}

mirror_on() {
  apply_monitor "hl.monitor({ output = \"$EXTERNAL\", mode = \"preferred\", position = \"auto\", scale = 1, mirror = \"$PRIMARY\" })" || return 1
  notify "Monitor Mode" "Mirror mode enabled"
}

mirror_off() {
  apply_monitor "hl.monitor({ output = \"$EXTERNAL\", mode = \"preferred\", position = \"auto\", scale = 1 })" || return 1
  notify "Monitor Mode" "Extended display enabled"
}

is_mirrored() {
  # hyprctl reports this as a mirrorOf field, not the prose "mirror of", and it
  # sits 23 lines into the block, so the old `grep -A 5` could not have reached
  # it even with the right pattern. Read the field by name instead.
  local mirror
  mirror=$(hyprctl monitors -j |
    jq -r --arg external "$EXTERNAL" '.[] | select(.name == $external) | .mirrorOf')
  [[ $mirror == "$PRIMARY" ]]
}

case "$MODE" in
on) mirror_on ;;
off) mirror_off ;;
toggle)
  if is_mirrored; then
    mirror_off
  else
    mirror_on
  fi
  ;;
esac
