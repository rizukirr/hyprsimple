#!/bin/bash

# List and join wireless networks, through whichever of NetworkManager or iwd
# is running. `wifi` is an alias for this in bash, zsh and fish.

# Answered before anything else in this file. The usage lived only in a comment
# here, so the way to find out what the second argument was for was to read the
# source, and the interface detection and backend choice below both come before
# any argument is looked at: on a machine with neither nmcli nor iwctl, asking
# for help got "No supported WiFi backend found" and exit 1.
usage() {
  cat <<'EOF'
Usage: wifi.sh [SSID] [PASSWORD]

  (no argument)  Rescan and list the networks in range.
  SSID           Connect. An open network, or one already saved, connects
                 straight away. A secured one asks for the password, as long
                 as there is a terminal to ask on.
  SSID PASSWORD  Connect without being asked, for a keybind or a script.

Examples:
  wifi
  wifi 'My Network'
  wifi 'My Network' 'my password'

Quote an SSID that contains spaces. Once a network has been joined it is
saved, so later connections need no password.

Uses NetworkManager if it is running, otherwise iwd.
EOF
}

case "${1:-}" in
-h | --help)
  usage
  exit 0
  ;;
esac

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
  elif [[ -t 0 ]]; then
    # --ask, or a secured network nmcli has no saved secret for fails without
    # ever asking, in nmcli's own words:
    #
    #   passwords or encryption keys are required to access the wireless
    #     network 'POCO F4'
    #   warning: password for '802-11-wireless-security.psk' not given in
    #     'passwd-file' and nmcli cannot ask without '--ask' option
    #   Error: connection activation failed: secrets were required but not
    #     provided
    #
    # Reported on a new install by someone typing `wifi "POCO F4"`, which is
    # the shape the usage line at the top of this file offers first.
    #
    # nmcli only prompts when a secret is actually missing, so an open network
    # and one already saved still connect without a word.
    nmcli --ask device wifi connect "$SSID"
  else
    # No terminal to prompt on: a keybind, a script, a service. --ask here
    # would wait on a prompt nobody can see, so the connection is attempted as
    # it always was and the advice is given here rather than left to nmcli's
    # message about passwd-file.
    nmcli device wifi connect "$SSID"
    # Captured on its own line. Inside `if ! cmd; then`, $? is the status of
    # the negation, which is 0, so the exit below would have flattened every
    # nmcli failure to the same code.
    status=$?
    if ((status != 0)); then
      echo "If '$SSID' needs a password, pass it: wifi.sh '$SSID' '<password>'" >&2
      exit "$status"
    fi
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
