#!/bin/bash

# Make NetworkManager the thing that runs the network, which is what the bar's
# network panel talks to.
#
# A machine that already runs NetworkManager is left exactly as it is. One that
# runs iwd by itself is moved over:
#
#   - the Wi-Fi networks iwd knows are copied into NetworkManager, passwords
#     included, so the machine comes back onto the same network unasked
#   - iwd is stopped and disabled, along with systemd-networkd and dhcpcd when
#     they are running, since two things configuring one interface fight
#   - NetworkManager is enabled and started
#
# If the machine was online before and is not within a short while after, the
# whole move is undone and the old services are started again.
#
# Nothing of iwd's is deleted. /var/lib/iwd and /etc/iwd stay, so going back is
#
#   sudo systemctl disable --now NetworkManager
#   sudo systemctl enable --now iwd
#
# A machine that runs neither is left alone, and so is one reached over SSH,
# where the move would cut the session it is being run from. Both are told how
# to do it by hand. --force moves an SSH session anyway.
#
# Exits 0 when there is nothing to do, when the move worked and when it was
# undone or declined. Exits 1 only when NetworkManager is not installed, so a
# caller can try again later.

set -u

# Overridable so the suite can arrange a machine without touching this one.
IWD_DIR="${HYPRSIMPLE_IWD_DIR:-/var/lib/iwd}"
NM_DIR="${HYPRSIMPLE_NM_DIR:-/etc/NetworkManager/system-connections}"
WAIT="${HYPRSIMPLE_NETWORK_WAIT:-45}"

active() { systemctl is-active --quiet "$1" 2>/dev/null; }
enabled() { systemctl is-enabled --quiet "$1" 2>/dev/null; }
online() {
  ip -4 route show default 2>/dev/null | grep -q . ||
    ip -6 route show default 2>/dev/null | grep -q .
}

if ! command -v nmcli >/dev/null 2>&1; then
  echo "NetworkManager is not installed, so the network is left as it is." >&2
  echo "Install it with: sudo pacman -S networkmanager" >&2
  exit 1
fi

if active NetworkManager; then
  echo "  NetworkManager already runs the network."
  exit 0
fi

by_hand() {
  echo "  To move to NetworkManager, which the bar's network panel needs, run:"
  echo "    hyprsimple-network-setup.sh"
}

if ! active iwd && ! enabled iwd; then
  echo "  This machine runs neither NetworkManager nor iwd, so its network is left as it is."
  echo "  The bar's network panel needs NetworkManager. To use it, stop what runs the"
  echo "  network now and run: sudo systemctl enable --now NetworkManager"
  exit 0
fi

if [[ -n ${SSH_CONNECTION:-} && ${1:-} != --force ]]; then
  echo "  This is an SSH session, and moving from iwd to NetworkManager would cut it."
  echo "  Run this at the machine itself: hyprsimple-network-setup.sh"
  exit 0
fi

echo "  Moving the network from iwd to NetworkManager."

# ---- copy the networks iwd knows ------------------------------------------------
#
# iwd keeps one file per network, named after it: <name>.psk for a password,
# <name>.open for none, <name>.8021x for enterprise. A name with characters
# iwd does not put in a file name is written as = followed by its bytes in hex.
#
# Each becomes a NetworkManager keyfile, written through sudo with mode 600 and
# never passed on a command line, where the password would show in the process
# list. One that NetworkManager already has a file for is left alone.

# What a keyfile value needs: a backslash doubled, and a leading space written
# as \s, since the format drops leading whitespace.
keyfile_value() {
  local v="${1//\\/\\\\}"
  [[ $v == " "* ]] && v="\\s${v:1}"
  printf '%s' "$v"
}

# How a network's name is written as ssid=, from its file name.
ssid_of() {
  local name="$1" hex out="" i
  if [[ $name == =* ]]; then
    hex="${name:1}"
    # As the list of bytes NetworkManager also accepts, which holds any name.
    for ((i = 0; i < ${#hex}; i += 2)); do out+="$((16#${hex:i:2}));"; done
    printf '%s' "$out"
  else
    keyfile_value "$name"
  fi
}

copied=0
skipped=()
copy_networks() {
  local file base kind name target secret
  # Listed through sudo as well: /var/lib/iwd is readable by root alone.
  while IFS= read -r file; do
    [[ -n $file ]] || continue
    base="${file##*/}"
    kind="${base##*.}"
    name="${base%.*}"
    case "$kind" in
    psk | open) ;;
    8021x)
      skipped+=("$name (enterprise, set it up again in NetworkManager)")
      continue
      ;;
    *) continue ;;
    esac

    target="$NM_DIR/hyprsimple-iwd-${name//[^a-zA-Z0-9._=-]/_}.nmconnection"
    sudo test -e "$target" && continue

    secret=""
    if [[ $kind == psk ]]; then
      # The passphrase when iwd kept it, otherwise the key derived from it,
      # which NetworkManager takes in the same place.
      secret=$(sudo sed -n 's/^Passphrase=//p' "$file" | head -n 1)
      [[ -n $secret ]] || secret=$(sudo sed -n 's/^PreSharedKey=//p' "$file" | head -n 1)
      if [[ -z $secret ]]; then
        skipped+=("$name (no password in iwd's file)")
        continue
      fi
    fi

    {
      printf '[connection]\nid=%s\ntype=wifi\n\n' "$(keyfile_value "${name#=}")"
      printf '[wifi]\nmode=infrastructure\nssid=%s\n\n' "$(ssid_of "$name")"
      if [[ $kind == psk ]]; then
        printf '[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n' "$(keyfile_value "$secret")"
      fi
      printf '[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n'
    } | sudo install -D -m 600 /dev/stdin "$target" && copied=$((copied + 1))
  done < <(sudo find "$IWD_DIR" -maxdepth 1 -type f \
    \( -name '*.psk' -o -name '*.open' -o -name '*.8021x' \) 2>/dev/null | sort)
}
copy_networks
echo "  Copied $copied Wi-Fi network(s) from iwd."
((${#skipped[@]} > 0)) && printf '  Not copied: %s\n' "${skipped[@]}"

# ---- swap the services ------------------------------------------------------------

was_online=no
online && was_online=yes

# What is stopped here is what is started again if the move is undone.
stopped=()
for unit in iwd.service systemd-networkd.socket systemd-networkd.service dhcpcd.service; do
  if active "$unit" || enabled "$unit"; then
    stopped+=("$unit")
  fi
done

undo() {
  sudo systemctl disable --now NetworkManager.service >/dev/null 2>&1
  sudo systemctl enable --now "${stopped[@]}" >/dev/null 2>&1
}

sudo systemctl disable --now "${stopped[@]}" >/dev/null 2>&1
if ! sudo systemctl enable --now NetworkManager.service >/dev/null 2>&1; then
  echo "  NetworkManager would not start, so the old services are started again."
  undo
  by_hand
  exit 0
fi

# A machine that was offline to begin with has nothing to come back to, so
# there is nothing to wait for and nothing to judge the move by.
if [[ $was_online == yes ]]; then
  echo "  Waiting up to ${WAIT}s for the network to come back..."
  back=no
  for ((i = 0; i < WAIT; i++)); do
    if online; then
      back=yes
      break
    fi
    sleep 1
  done
  if [[ $back == no ]]; then
    echo "  The network did not come back under NetworkManager, so the move is undone."
    undo
    echo "  iwd runs the network again. The bar's network panel needs NetworkManager."
    by_hand
    exit 0
  fi
fi

echo "  NetworkManager runs the network now. iwd is disabled, and its files are kept."
echo "  To go back: sudo systemctl disable --now NetworkManager && sudo systemctl enable --now iwd"
exit 0
