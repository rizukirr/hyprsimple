echo "Enable thermald only on Intel laptops, disable it elsewhere"

# thermald is an Intel-specific thermal policy daemon. hyprsimple used to install
# and enable it unconditionally, so AMD machines and desktops have been running a
# daemon that does nothing for them.

CHECK="$HOME/.local/bin/hyprsimple-hw-intel-laptop.sh"
[[ -x $CHECK ]] || exit 0

if bash "$CHECK"; then
  # Intel laptop: make sure it is actually installed and running
  if ! pacman -Qi thermald &>/dev/null; then
    sudo pacman -S --needed --noconfirm thermald || exit 1
  fi
  systemctl is-enabled thermald &>/dev/null || sudo systemctl enable --now thermald
else
  # Not an Intel laptop: stop and disable, but leave the package alone in case
  # something else pulled it in
  if systemctl is-enabled thermald &>/dev/null; then
    echo "  Not an Intel laptop - disabling thermald"
    sudo systemctl disable --now thermald
  fi
fi
