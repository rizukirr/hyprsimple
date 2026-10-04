#!/bin/bash

# Show the current PipeWire volume as a notification.
#
# Every one carries the same hint, which is how the bar knows to show it in
# place of the last one instead of stacking a column of them up.

SAME=(-h string:x-canonical-private-synchronous:volume)

# Nothing rather than a level, when wpctl cannot answer.
#
# awk printed 0 for any line it could not parse, so a failed read showed
# "Volume: 0%" with an empty bar: a specific, wrong number rather than a sign
# that nothing was read. The keybinds run this after a set-volume that
# succeeded, but the default sink can go between the two calls, which is what a
# bluetooth headset disconnecting looks like.
get_volume() {
  local vol level
  vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) || return 1
  if grep -q MUTED <<<"$vol"; then
    printf 'muted'
    return 0
  fi
  # wpctl answers "Volume: 0.55". Anything else is not a volume.
  level=$(awk '/^Volume:/ { printf("%d", $2 * 100) }' <<<"$vol")
  [[ $level =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$level"
}

# printf with no arguments prints its format string once, so
# `printf 'X%.0s' $(seq 1 0)` yields one X rather than none. That put a filled
# block in the bar at 0 and an empty one at 100, and made the bar 21 characters
# wide at both ends instead of 20. A loop has no such edge.
repeat_char() {
  local count=$1 char=$2 i out=""
  for ((i = 0; i < count; i++)); do out+="$char"; done
  printf '%s' "$out"
}

show_notification() {
  vol=$1
  if [[ "$vol" == "muted" ]]; then
    notify-send -u low -t 1500 "${SAME[@]}" "Volume" "Muted 🔇"
  else
    filled=$((vol / 5))
    empty=$((20 - filled))
    bar="$(repeat_char "$filled" '█')$(repeat_char "$empty" '░')"
    notify-send -u low -t 1500 "${SAME[@]}" "Volume: $vol%" "$bar"
  fi
}

if ! level=$(get_volume); then
  notify-send -u low -t 1500 "${SAME[@]}" "Volume" "Could not read the current volume"
  exit 1
fi

show_notification "$level"
