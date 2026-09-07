#!/bin/bash

# Battery notification script - reduce brightness when battery is low
# Designed to be run by systemd timer every 30 seconds

BATTERY_THRESHOLD=(20 15 10 5 3)
# Brightness to drop to once the battery reaches the first threshold. Fixed on
# purpose: dimming hard and early buys more runtime than stepping down slowly.
LOW_BATTERY_BRIGHTNESS=5
FLAG_FILE="/tmp/battery-notification-flag"
# Where the brightness was before a low battery dimmed the screen, so charging
# can put it back. Beside the flag, and overridable so the suite never writes
# to the real one.
BRIGHTNESS_FILE="${HYPRSIMPLE_BRIGHTNESS_FILE:-/tmp/battery-brightness-before-dim}"

get_battery_percentage() {
  upower -i "$(upower -e | grep 'BAT')" |
    awk -F: '/percentage/ {
      gsub(/[%[:space:]]/, "", $2);
      val=$2;
      printf("%d\n", (val+0.5))
      exit
    }'
}

get_battery_state() {
  upower -i "$(upower -e | grep 'BAT')" | grep -E "state" | awk '{print $2}'
}

BATTERY_LEVEL=$(get_battery_percentage)
BATTERY_STATE=$(get_battery_state)

if [[ "$BATTERY_STATE" == "discharging" ]]; then
  # The lowest threshold the battery has fallen past, not every threshold it is
  # under. Acting inside the loop meant one 9% reading dimmed the screen three
  # times and sent three identical notifications, because the flag file only
  # ever holds the last threshold written, so the next iteration compared
  # against a different number and fired again. At 2% it was five.
  #
  # Comparing rather than taking the last match, which would be shorter and
  # would rely on BATTERY_THRESHOLD staying in descending order. Nothing states
  # that invariant and nothing enforces it.
  crossed=""
  for threshold in "${BATTERY_THRESHOLD[@]}"; do
    if [[ "$BATTERY_LEVEL" -le "$threshold" ]] &&
      { [[ -z $crossed ]] || [[ "$threshold" -lt "$crossed" ]]; }; then
      crossed="$threshold"
    fi
  done

  if [[ -n $crossed ]]; then
    # Once per crossing, for the dimming as well as the message. Falling into a
    # lower band writes a new value here and so acts again, which is the
    # escalation this file was always for.
    #
    # The dimming used to sit outside this check and so ran on every tick. The
    # timer fires every 30 seconds, so from the moment the battery passed 20%
    # the screen was forced back to 5% twice a minute and could not be turned
    # up: raise it to read something, and half a minute later it was dark
    # again. Dimming hard and early is deliberate. Pinning it there, against
    # the user, was not.
    if [[ ! -f "$FLAG_FILE" ]] || [[ $(cat "$FLAG_FILE" 2>/dev/null) != "$crossed" ]]; then
      # Remembered before dimming, so plugging in can put it back. Only on the
      # first crossing: falling into a lower band dims again from 5%, and
      # recording that would make 5% the value restored later.
      if [[ ! -f $BRIGHTNESS_FILE ]]; then
        current_brightness() { brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%'; }
        printf '%s\n' "$(current_brightness)" >"$BRIGHTNESS_FILE"
      fi
      brightnessctl set "${LOW_BATTERY_BRIGHTNESS}"%
      notify-send -u critical "Battery Low" "Battery at ${BATTERY_LEVEL}%, brightness reduced to ${LOW_BATTERY_BRIGHTNESS}%"
      echo "$crossed" >"$FLAG_FILE"
    fi
  fi
else
  # Clear flag when charging/charged to allow new notifications on next discharge
  rm -f "$FLAG_FILE"

  # And put the brightness back.
  #
  # The dimming had no counterpart, so a low battery took the screen to 5% and
  # left it there. Plugging in cleared the flag and nothing else: the screen
  # stayed dark until it was raised by hand, every time, long after the
  # notification that explained it had gone. Measured on a live machine
  # charging at 4%, with the panel sitting at 5% and no way to tell why.
  #
  # Its own record rather than `brightnessctl -s` and `-r`. hypridle already
  # uses that save slot for the idle dim, so the two would overwrite each
  # other: idle after a battery dim would save 5% over the real value, and the
  # restore here would put back 5%.
  if [[ -f $BRIGHTNESS_FILE ]]; then
    saved=$(cat "$BRIGHTNESS_FILE" 2>/dev/null)
    now=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')
    # Only when the screen is still where the dimming left it. Anything else
    # was set deliberately since, and is not ours to undo.
    if [[ $now == "$LOW_BATTERY_BRIGHTNESS" && $saved =~ ^[0-9]+$ && $saved != "$LOW_BATTERY_BRIGHTNESS" ]]; then
      brightnessctl set "${saved}%"
      notify-send "Battery" "Charging, brightness restored to ${saved}%" -t 2000
    fi
    rm -f "$BRIGHTNESS_FILE"
  fi
fi
