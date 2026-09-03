#!/bin/bash

# Usage: wifi-powersave.sh <on|off>

if [[ $1 != on && $1 != off ]]; then
  echo "Usage: wifi-powersave.sh <on|off>" >&2
  exit 1
fi

# iw exits 2 on a value it does not accept and 1 on a missing one. Sending that
# to /dev/null and notifying regardless is how this reported success while
# changing nothing. A machine can have more than one wireless interface, so one
# success is enough to report success.
# The sysfs root is overridable so both the has-wireless and no-wireless paths
# can be tested on one machine, and so a runner without a wireless interface
# can exercise the success path at all.
SYSFS_NET="${HYPRSIMPLE_SYSFS_NET:-/sys/class/net}"

changed=0
for wireless in "$SYSFS_NET"/*/wireless; do
  [[ -d $wireless ]] || continue
  iface="$(basename "$(dirname "$wireless")")"
  if sudo iw dev "$iface" set power_save "$1" 2>/dev/null; then
    changed=$((changed + 1))
  fi
done

if (( changed > 0 )); then
  notify-send "WiFi" "Power save: $1"
else
  notify-send -u critical "WiFi" "Could not set power save to $1"
  exit 1
fi
