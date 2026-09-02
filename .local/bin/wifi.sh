#!/bin/bash

# Usage: wifi.sh [SSID] [PASSWORD]
#   no args   -> rescan and list networks
#   SSID      -> connect (open network, or known/saved network)
#   SSID PASS -> connect with passphrase

# Auto-detect WiFi interface. A glob rather than parsing ls output, so the
# shell splits the paths instead of a newline doing it.
IFACE=""
for wireless in /sys/class/net/*/wireless; do
  [[ -d $wireless ]] || continue
  IFACE=$(basename "$(dirname "$wireless")")
  break
done

if [[ -z $IFACE ]]; then
  echo "No WiFi interface found"
  exit 1
fi

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
