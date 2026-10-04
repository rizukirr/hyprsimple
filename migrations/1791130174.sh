echo "Run the network with NetworkManager, which the bar's network panel needs"

# hyprsimple installed nothing to run the network and used whatever the machine
# came with. The bar's network panel talks to NetworkManager, so on a machine
# that runs iwd by itself it had nothing to list and nothing to connect with.
#
# The update installs networkmanager from packages.txt before migrations run.
# The script below does the rest, and is the same one install.sh runs:
#
# A machine already on NetworkManager is left exactly as it is.
#
# A machine on iwd is moved over. The Wi-Fi networks iwd knows are copied
# across with their passwords, iwd is disabled, with systemd-networkd and
# dhcpcd when they run, and NetworkManager is started. If the machine was
# online and is not again within 45 seconds, all of that is undone and iwd
# runs the network as before.
#
# A machine that runs neither, or one reached over SSH, is left alone and told
# what to run.
#
# It asks for your password only when there is something to move.

SETUP="$HOME/.local/bin/hyprsimple-network-setup.sh"

if [[ ! -x $SETUP ]]; then
  echo "$SETUP is missing, so the network is left as it is." >&2
  exit 1
fi

# Its exit status is this migration's. It is 1 only when NetworkManager is not
# installed, which the next update can put right. A move that was undone or
# declined is 0: trying again on every update would cut the network each time.
"$SETUP"
