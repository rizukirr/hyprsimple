#!/bin/bash

# Usage: wifi.sh [SSID] [PASSWORD]
#   no args   -> rescan and list networks
#   SSID      -> connect (open network, or known/saved network)
#   SSID PASS -> connect with passphrase

# Auto-detect WiFi interface. A glob rather than parsing ls output, so the
# shell splits the paths instead of a newline doing it.
#
# phy80211 first: cfg80211 creates it for every wireless netdev, unconditionally.
# The wireless directory next to it is the WEXT compatibility layer, which is a
# kernel option (CONFIG_CFG80211_WEXT) and can simply be absent on a machine
# whose WiFi works perfectly well. Looking only at that one was the bug.
#
# The sysfs root is overridable so both the has-wireless and no-wireless paths
# can be tested on one machine, matching wifi-powersave.sh.
SYSFS_NET="${HYPRSIMPLE_SYSFS_NET:-/sys/class/net}"

IFACE=""
for marker in "$SYSFS_NET"/*/phy80211 "$SYSFS_NET"/*/wireless; do
  [[ -e $marker ]] || continue
  IFACE=$(basename "$(dirname "$marker")")
  break
done

# Detect the active WiFi backend. Prefer whichever service is actually
# running so we never run iwctl on a NetworkManager/wpa_supplicant host
# (that race prints "No station on device" at boot). NetworkManager wins
# ties since it's the common default; fall back to iwd.
detect_backend() {
  if command -v nmcli &>/dev/null && systemctl is-active --quiet NetworkManager; then
    echo nmcli
  elif command -v iwctl &>/dev/null && systemctl is-active --quiet iwd; then
    echo iwd
  elif command -v nmcli &>/dev/null; then
    echo nmcli
  elif command -v iwctl &>/dev/null; then
    echo iwd
  else
    echo none
  fi
}

BACKEND=$(detect_backend)
SSID=$1
PASS=$2

case "$BACKEND" in
nmcli)
  # No interface check here on purpose. NetworkManager finds its own device,
  # and nothing in this branch uses $IFACE. Requiring one meant that a machine
  # where the interface is not visible in sysfs was told "No WiFi interface
  # found" without nmcli ever being asked, when nmcli would have worked.
  nmcli device wifi rescan 2>/dev/null
  if [[ -z $SSID ]]; then
    nmcli --fields IN-USE,SSID,SIGNAL,SECURITY device wifi list
    exit
  fi
  if [[ -n $PASS ]]; then
    nmcli device wifi connect "$SSID" password "$PASS"
  else
    nmcli device wifi connect "$SSID"
  fi
  ;;
iwd)
  # iwctl needs the interface by name, so this is where the check belongs.
  if [[ -z $IFACE ]]; then
    echo "No WiFi interface found" >&2
    exit 1
  fi
  iwctl station "$IFACE" scan
  if [[ -z $SSID ]]; then
    iwctl station "$IFACE" get-networks
    exit
  fi
  if [[ -n $PASS ]]; then
    iwctl --passphrase "$PASS" station "$IFACE" connect "$SSID"
  else
    iwctl station "$IFACE" connect "$SSID"
  fi
  ;;
*)
  echo "No supported WiFi backend found (need NetworkManager/nmcli or iwd/iwctl)"
  exit 1
  ;;
esac
