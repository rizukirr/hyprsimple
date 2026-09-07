#!/bin/bash

ON_TEMP=4000
OFF_TEMP=6000

# The current temperature, or nothing when hyprsunset is not answering.
#
# Anchored to a bare number. This was `hyprctl hyprsunset temperature | grep
# -oE '[0-9]+'`, and hyprctl prints its connection error on stdout rather than
# stderr, so the redirection to /dev/null did not hide it and the scrape read
# the digits out of the socket path instead:
#
#   Couldn't connect to /run/user/1000/hypr/efb5...1788756256_4119465/.hyprsunset.sock. (3)
#
# came back as 1000, 50993780079460, 0, 1363, 2166, 2, 1, 9, 1788756256,
# 4119465, 3. That never equals 6000, so the script took its else branch and
# asked for 6000, the daylight end, on a key press meant to warm the screen.
#
# hyprsunset answers a query with the number on its own and a set with "ok".
current_temperature() {
  local out
  out=$(hyprctl hyprsunset temperature 2>/dev/null) || return 1
  [[ $out =~ ^[0-9]+$ ]] || return 1
  printf '%s\n' "$out"
}

# Waited for, not slept past. This was `sleep 1`, which is a guess about how
# long hyprsunset takes to open its socket, and every guess that comes up short
# landed in the branch above.
# Through the unit, not `uwsm app --`. A scope started here would have no
# restart policy, which is the thing that left hyprsunset gone for the rest of
# a session after a suspend.
if ! pgrep -x hyprsunset >/dev/null; then
  systemctl --user start hyprsunset.service 2>/dev/null &
  waited=0
  limit="${HYPRSIMPLE_SUNSET_WAIT:-50}"
  while ! current_temperature >/dev/null && ((waited < limit)); do
    sleep 0.1
    waited=$((waited + 1))
  done
fi

# Said rather than assumed. The old script reported a temperature change
# whether or not hyprctl had accepted one, so a session with no hyprsunset in
# it answered every press with "Daylight screen temperature (6000K)" and
# changed nothing. Pressing again did the same, so the nightlight could not be
# turned on at all, and nothing on screen said why.
if ! CURRENT_TEMP=$(current_temperature); then
  notify-send -u critical "Nightlight" "hyprsunset is not responding, so the screen temperature is unchanged"
  exit 1
fi

if [[ $CURRENT_TEMP == "$OFF_TEMP" ]]; then
  TARGET=$ON_TEMP
  LABEL="Warm screen temperature"
else
  TARGET=$OFF_TEMP
  LABEL="Daylight screen temperature"
fi

if [[ $(hyprctl hyprsunset temperature "$TARGET" 2>/dev/null) == "ok" ]]; then
  notify-send "Nightlight" "$LABEL (${TARGET}K)"
else
  notify-send -u critical "Nightlight" "hyprsunset would not set ${TARGET}K, so the screen temperature is unchanged"
  exit 1
fi
