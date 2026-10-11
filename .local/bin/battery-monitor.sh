#!/bin/bash

# Battery notification script - reduce brightness and switch to the power-saver
# profile when battery is low, and put both back when the charger goes in.
# Run by a systemd timer every 30 seconds, and by the bar at the moment the
# charger is plugged in or pulled out.

BATTERY_THRESHOLD=(20 15 10 5 3)
# Brightness to drop to once the battery reaches the first threshold. Fixed on
# purpose: dimming hard and early buys more runtime than stepping down slowly.
LOW_BATTERY_BRIGHTNESS=5
# The threshold last acted on, so a crossing acts once. Overridable for the
# same reason as the record below: a suite that ran against the real path
# deleted the live flag out from under the running service.
FLAG_FILE="${HYPRSIMPLE_BATTERY_FLAG:-/tmp/battery-notification-flag}"
# Where the brightness was before a low battery dimmed the screen, so charging
# can put it back. Beside the flag, and overridable so the suite never writes
# to the real one.
BRIGHTNESS_FILE="${HYPRSIMPLE_BRIGHTNESS_FILE:-/tmp/battery-brightness-before-dim}"
# The power profile to switch to with the dimming, and where the one in use
# before is kept so charging can put it back.
#
# Not in /tmp like the two above. power-profiles-daemon keeps its profile
# across a reboot and /tmp does not, so a machine that ran flat in power-saver
# would come back still in it, with the record of what to return to gone.
LOW_BATTERY_PROFILE=power-saver
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hyprsimple"
PROFILE_FILE="${HYPRSIMPLE_PROFILE_FILE:-$STATE_DIR/battery-profile-before-low}"

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
      #
      # A record that is not a number counts as no record. It lives in /tmp,
      # which anything can leave a file in, and an empty one left behind would
      # otherwise stop the real brightness ever being written and so lose the
      # restore silently.
      recorded=$(cat "$BRIGHTNESS_FILE" 2>/dev/null)
      now=$(brightnessctl -m 2>/dev/null | cut -d, -f4 | tr -d '%')

      # A screen already at the dim level has no before value to read.
      #
      # hypridle dims to the same 5 after ten minutes idle, through
      # brightnessctl -s and -r, and it gets there first: its timeout is ten
      # minutes and the battery falls past a threshold whenever it does. A
      # crossing during that idle used to record 5 as the brightness to go back
      # to, and the guard on the restore rejects 5, so the screen stayed at 5
      # when the charger went in. Traced end to end:
      #
      #   80, idle dims to 5, crossing records 5, user returns and hypridle
      #   restores 80, next crossing dims to 5 again, charging restores nothing.
      #
      # Neither recording nor dimming here. The screen is where it needs to be
      # already, and the value that would be recorded is another program's, not
      # the user's. The next crossing after hypridle restores reads the real
      # one.
      if [[ $now != "$LOW_BATTERY_BRIGHTNESS" ]]; then
        if [[ ! $recorded =~ ^[0-9]+$ ]]; then
          printf '%s\n' "$now" >"$BRIGHTNESS_FILE"
        fi
        brightnessctl set "${LOW_BATTERY_BRIGHTNESS}"%
      fi

      # The same shape for the power profile: remember the one in use, once,
      # then switch. A machine already in power-saver has nothing to remember
      # and is not sent back anywhere later. One without power-profiles-daemon
      # is only dimmed.
      saver=""
      if command -v powerprofilesctl >/dev/null 2>&1; then
        profile=$(powerprofilesctl get 2>/dev/null)
        if [[ -n $profile && $profile != "$LOW_BATTERY_PROFILE" ]]; then
          if [[ ! $(cat "$PROFILE_FILE" 2>/dev/null) =~ ^(balanced|performance)$ ]]; then
            mkdir -p "$(dirname "$PROFILE_FILE")"
            printf '%s\n' "$profile" >"$PROFILE_FILE"
          fi
          powerprofilesctl set "$LOW_BATTERY_PROFILE"
        fi
        # Said only if it is so. The switch can be refused.
        [[ $(powerprofilesctl get 2>/dev/null) == "$LOW_BATTERY_PROFILE" ]] && saver=", power saver on"
      fi
      notify-send -u critical "Battery Low" "Battery at ${BATTERY_LEVEL}%, brightness reduced to ${LOW_BATTERY_BRIGHTNESS}%${saver}"
      echo "$crossed" >"$FLAG_FILE"
    fi
  fi
else
  # Whether a low battery was acted on since the charger was last in. Read
  # before anything is cleared, because it decides whether to say anything.
  warned=false
  [[ -f $FLAG_FILE || -f $BRIGHTNESS_FILE || -f $PROFILE_FILE ]] && warned=true
  restored=()

  # Clear flag when charging/charged to allow new notifications on next discharge
  rm -f "$FLAG_FILE"

  # The power profile goes back, if it is still the one a low battery chose.
  # Anything else was picked since, in the system panel or a terminal, and is
  # not ours to undo.
  if [[ -f $PROFILE_FILE ]]; then
    saved=$(cat "$PROFILE_FILE" 2>/dev/null)
    if [[ $saved =~ ^(balanced|performance)$ ]] && command -v powerprofilesctl >/dev/null 2>&1 &&
      [[ $(powerprofilesctl get 2>/dev/null) == "$LOW_BATTERY_PROFILE" ]] &&
      powerprofilesctl set "$saved"; then
      restored+=("${saved} mode")
    fi
    rm -f "$PROFILE_FILE"
  fi

  # And the brightness.
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
    # Whenever the screen is darker than it was before the dimming.
    #
    # This used to restore only a screen still at exactly the dim level, on
    # the reasoning that any other value was chosen deliberately. But 5% is
    # too dark to work at, so the usual thing is to nudge it up to read, and
    # that nudge then cancelled the restore: the charger went in, the screen
    # stayed dim and nothing was said. A screen set brighter than before is
    # still left alone.
    if [[ $saved =~ ^[0-9]+$ && $now =~ ^[0-9]+$ ]] && ((now < saved)); then
      brightnessctl set "${saved}%"
      restored+=("brightness ${saved}%")
    fi
    rm -f "$BRIGHTNESS_FILE"
  fi

  # Said once, after a low battery, whether or not there was anything left to
  # put back. Plugging in at a healthy level says nothing: the bar shows that.
  if [[ $warned == true ]]; then
    if ((${#restored[@]} == 2)); then
      notify-send "Charging" "Battery at ${BATTERY_LEVEL}%, ${restored[0]} and ${restored[1]} restored"
    elif ((${#restored[@]} == 1)); then
      notify-send "Charging" "Battery at ${BATTERY_LEVEL}%, ${restored[0]} restored"
    else
      notify-send "Charging" "Battery at ${BATTERY_LEVEL}%"
    fi
  fi
fi
