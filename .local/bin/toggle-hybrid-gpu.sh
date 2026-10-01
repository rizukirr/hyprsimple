#!/bin/bash

# Turn the discrete GPU off or on through supergfxd, and say which of the two
# actually happened.
#
#   Hybrid      the NVIDIA card is powered and takes work through prime-run
#   Integrated  the card is off and only the integrated GPU runs
#
# Run from a terminal. It takes no arguments. Switching never calls sudo,
# because supergfxd does the privileged work over D-Bus. The first run is the
# exception: it sets supergfxctl up, and that needs sudo and an AUR helper.
#
# supergfxd will not go from Vfio to Hybrid in one step. It answers "You must
# change to Integrated before you can change to Hybrid" and changes nothing,
# which is how a laptop sat in Vfio with a card nothing on the host could use.
# From Vfio this asks for Integrated first.
#
# That answer is a line of text, and nothing here relies on it coming with a
# failing exit status. The mode and the pending action are asked for after
# every request, and the report is built from those.

# Bounded, because a supergfxd that has wedged blocks its clients without end.
QUERY_WAIT=3
CMDLINE_FILE="${HYPRSIMPLE_CMDLINE_FILE:-/proc/cmdline}"

die() {
  echo "GPU: $*" >&2
  exit 1
}

# The first run. supergfxctl is an AUR package that compiles from source and
# brings a system daemon with it. install.sh set it up on every hybrid machine
# for a short while, which put a compile and a daemon in front of people who
# never wanted the card switched. It is set up here, by whoever runs this.
#
# The helper is run without its unattended flags on purpose. It then shows its
# own review and asks before it builds, and that is the confirmation for the
# whole setup.
#
# The config is written before the service first starts, and only when there
# is none, so a mode someone already chose is kept. The values are supergfxd's
# own defaults. The path is overridable so the suite never writes to /etc.
setup_supergfxctl() {
  local conf="${HYPRSIMPLE_SUPERGFXD_CONF:-/etc/supergfxd.conf}"
  local detect="$HOME/.local/bin/hyprsimple-aur-helper.sh"
  local other helper

  # The switchers upstream says supergfxctl conflicts with. Two of them
  # managing one card is worse than having neither.
  for other in optimus-manager system76-power bbswitch bbswitch-dkms; do
    if pacman -Qq "$other" >/dev/null 2>&1; then
      die "$other is installed, and supergfxctl conflicts with it. Remove $other first if you want to switch the GPU with this toggle."
    fi
  done

  [[ -r $detect ]] || die "missing helper: hyprsimple-aur-helper.sh. Run hyprsimple-update."
  # shellcheck source=/dev/null
  source "$detect"
  helper="$(aur_helper)" ||
    die "supergfxctl comes from the AUR, and no AUR helper was found. Install paru or yay, then run this again."

  echo "GPU: supergfxctl is not installed, so this run sets it up and switches nothing:"
  echo "  1. $helper builds supergfxctl from the AUR, which compiles it from source"
  echo "  2. $conf is written, if there is none"
  echo "  3. the supergfxd service is enabled and started"

  "$helper" -S supergfxctl || die "$helper did not install supergfxctl, so nothing else was changed"
  command -v supergfxctl >/dev/null 2>&1 ||
    die "supergfxctl is still not installed, so nothing else was changed"

  if [[ ! -e $conf ]]; then
    printf '%s\n' \
      '{' \
      '  "mode": "Hybrid",' \
      '  "vfio_enable": false,' \
      '  "vfio_save": false,' \
      '  "always_reboot": false,' \
      '  "no_logind": false,' \
      '  "logout_timeout_s": 180,' \
      '  "hotplug_type": "None"' \
      '}' | sudo tee "$conf" >/dev/null ||
      echo "GPU: could not write $conf, so supergfxd will start with its own defaults." >&2
  fi

  sudo systemctl enable --now supergfxd ||
    die "supergfxd would not start. Check it with: systemctl status supergfxd"

  echo "GPU: supergfxctl is set up in Hybrid mode, which is how this machine was already running."
  echo "GPU: run toggle-hybrid-gpu.sh again to turn the NVIDIA GPU off."
}

if ! command -v supergfxctl >/dev/null 2>&1; then
  setup_supergfxctl
  exit 0
fi

current_mode() { timeout "$QUERY_WAIT" supergfxctl -g 2>/dev/null; }

mode="$(current_mode)" || mode=""
[[ -n $mode ]] ||
  die "supergfxd is not answering. Check it with: systemctl status supergfxd. Your user also has to be in one of the groups wheel, users, adm or sudo."

case "$mode" in
Hybrid) steps=(Integrated) ;;
Integrated) steps=(Hybrid) ;;
Vfio) steps=(Integrated Hybrid) ;;
*) die "supergfxd is in $mode mode, which this toggle does not switch. Use supergfxctl -m <mode> directly." ;;
esac
target="${steps[-1]}"

# Only on the way to Hybrid, which is the direction that needs the driver.
# module_blacklist= makes the kernel refuse the module outright, so supergfxd
# would accept the switch and the card would still never come up.
# modprobe.blacklist= only stops automatic loading, and supergfxd loads the
# driver by name, so that one is reported and the switch goes ahead.
if [[ $target == Hybrid ]]; then
  cmdline=""
  [[ -r $CMDLINE_FILE ]] && cmdline="$(<"$CMDLINE_FILE")"
  if [[ $cmdline =~ (^|[[:space:]])module_blacklist=[^[:space:]]*nvidia ]]; then
    die "the kernel command line carries module_blacklist= for the NVIDIA modules, so the driver cannot load and Hybrid mode cannot work. Remove that parameter from your boot entry, reboot, then run this again."
  fi
  if [[ $cmdline =~ (^|[[:space:]])modprobe\.blacklist=[^[:space:]]*nvidia ]]; then
    echo "GPU: the kernel command line carries modprobe.blacklist= for the NVIDIA modules. supergfxd loads the driver itself, so the switch is going ahead. If the card does not come up in Hybrid mode, remove that parameter and reboot." >&2
  fi
fi

# What supergfxctl said in answer to the last request. Kept and not printed,
# because for a request it accepted the report below says the same thing from
# the mode and the pending action, and the user would read it twice. It is
# shown when the request did not go through, which is when it is the reason.
answer=""
refused() {
  [[ -n $answer ]] && echo "$answer" >&2
  die "$@"
}

for step in "${steps[@]}"; do
  answer="$(supergfxctl -m "$step" 2>&1)" || refused "supergfxctl could not ask for $step mode"
  mode="$(current_mode)" || mode=""
  # A step that is not the last has to have landed before the next is asked
  # for, or the second request is refused for the same reason as the first.
  if [[ $step != "$target" && $mode != "$step" ]]; then
    refused "asked for $step mode on the way to $target, and supergfxd is still in ${mode:-an unknown} mode"
  fi
done

if [[ $mode == "$target" ]]; then
  echo "GPU: switched to $target mode"
  exit 0
fi

pending="$(timeout "$QUERY_WAIT" supergfxctl -p 2>/dev/null)" || pending=""
if [[ -z $pending || $pending == "No action required" ]]; then
  refused "supergfxd did not take the switch to $target mode and is still in ${mode:-an unknown} mode"
fi

echo "GPU: $target mode requested. supergfxd reports: $pending"
echo "GPU: log out and back in to finish the switch. Until then the mode is still $mode."
