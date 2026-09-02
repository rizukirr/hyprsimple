#!/bin/bash

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
    sudo systemctl restart systemd-resolved
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

sudo systemctl restart systemd-resolved
echo "DNS set to $DNS_NAME ($DNS)"
