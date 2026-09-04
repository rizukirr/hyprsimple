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

# phy80211 first: cfg80211 creates it for every wireless netdev,
# unconditionally. The wireless directory beside it is the WEXT compatibility
# layer, which is a kernel option and can be absent on a machine whose WiFi
# works. Looking only at that one missed the interface entirely.
#
# Sorted unique, because an interface usually has both markers and this loop
# acts on every interface rather than stopping at the first. Without that it
# would run iw twice per interface and count each one twice.
mapfile -t ifaces < <(
  for marker in "$SYSFS_NET"/*/phy80211 "$SYSFS_NET"/*/wireless; do
    [[ -e $marker ]] && basename "$(dirname "$marker")"
  done | LC_ALL=C sort -u
)

changed=0
for iface in "${ifaces[@]}"; do
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
