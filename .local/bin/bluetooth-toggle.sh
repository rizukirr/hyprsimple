#!/bin/bash

# Read the adapter's power state through bluetoothctl, which is what the writes
# below already use.
#
# This used to ask dbus about /org/bluez/hci0 by name. An adapter that comes up
# as anything else, which a USB dongle does whenever a built-in radio already
# holds hci0, made that read fail every time. is_powered was then permanently
# false, so the toggle only ever powered the adapter on and never off: the same
# one-way switch monitor-mirror-toggle.sh had.
#
# bluetoothctl acts on the default controller, so reading and writing now agree
# about which adapter is meant, whatever it is called.
is_powered() {
  bluetoothctl show 2>/dev/null | grep -q "Powered: yes"
}

has_adapter() {
  bluetoothctl show 2>/dev/null | grep -q "^Controller "
}

case "$1" in
toggle)
  if ! has_adapter; then
    notify-send "Bluetooth" "No Bluetooth adapter found" -u critical -t 3000
    exit 1
  fi
  if is_powered; then
    bluetoothctl power off
  else
    bluetoothctl power on
  fi
  ;;
status)
  if is_powered; then
    echo "true"
  else
    echo "false"
  fi
  ;;
*)
  # To stderr, so a caller reading `status` from stdout is never handed this
  # instead of true or false.
  echo "Usage: $(basename "$0") {toggle|status}" >&2
  exit 1
  ;;
esac
