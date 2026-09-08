#!/bin/bash

# Turn idle locking on or off, and say which of the two actually happened.
#
# This backgrounded hypridle, discarded its output and notified regardless:
#
#   uwsm app -- hypridle >/dev/null 2>&1 &
#   notify-send "Idle" "Now locking when idle"
#
# A hypridle that refuses to start left the user told the screen would lock on
# idle when nothing was going to lock it. That is worse than the other
# announce-regardless bugs in this project: the rest waste a keypress, this one
# tells you a screen lock is armed when it is not.
#
# Waited for and checked, the same way screen-record.sh checks its recorder and
# virtual-mirror-toggle.sh its mirror. Overridable so the suite need not sit
# through the wait.
IDLE_START_WAIT="${HYPRSIMPLE_IDLE_START_WAIT:-0.4}"

if pgrep -x hypridle >/dev/null; then
  if pkill -x hypridle; then
    notify-send "Idle" "Stopped locking when idle"
  else
    notify-send -u critical "Idle" "Could not stop hypridle, so the screen still locks when idle"
    exit 1
  fi
else
  uwsm app -- hypridle >/dev/null 2>&1 &

  sleep "$IDLE_START_WAIT"
  if ! pgrep -x hypridle >/dev/null; then
    notify-send -u critical "Idle" "hypridle would not start, so the screen will not lock when idle"
    exit 1
  fi

  notify-send "Idle" "Now locking when idle"
fi
