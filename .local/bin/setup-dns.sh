#!/bin/bash

# systemd-resolved is not in packages.txt, so it is not guaranteed to be the
# resolver on this machine. Writing resolved.conf.d on a host that does not use
# it changes nothing, and the script used to report success anyway.
if ! systemctl is-active --quiet systemd-resolved; then
  echo "systemd-resolved is not running, so this script cannot set your DNS." >&2
  echo "Check what manages /etc/resolv.conf on this machine." >&2
  exit 1
fi

echo "Select DNS provider:"
echo "1) Cloudflare (1.1.1.1)"
echo "2) Google (8.8.8.8)"
echo "3) DHCP (default)"
read -rp "Choice [1-3]: " choice

case $choice in
  1)
    DNS="1.1.1.1 1.0.0.1"
    DNS_NAME="Cloudflare"
    ;;
  2)
    DNS="8.8.8.8 8.8.4.4"
    DNS_NAME="Google"
    ;;
  3)
    echo "Using DHCP defaults"
    sudo rm -f /etc/systemd/resolved.conf.d/dns.conf
    sudo systemctl restart systemd-resolved ||
      { echo "Could not restart systemd-resolved" >&2; exit 1; }
    echo "DNS reset to DHCP"
    exit 0
    ;;
  *)
    echo "Invalid choice"
    exit 1
    ;;
esac

sudo mkdir -p /etc/systemd/resolved.conf.d
sudo tee /etc/systemd/resolved.conf.d/dns.conf <<EOF >/dev/null
[Resolve]
DNS=$DNS
DNSOverTLS=opportunistic
EOF

# Announcing the change only if the restart took. systemctl exits 5 on a unit
# that does not exist and non-zero on one that fails to start, and this used to
# print success either way, on a machine whose DNS was then broken.
sudo systemctl restart systemd-resolved ||
  { echo "Could not restart systemd-resolved, DNS unchanged" >&2; exit 1; }
echo "DNS set to $DNS_NAME ($DNS)"
