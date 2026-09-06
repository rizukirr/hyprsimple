#!/bin/bash

set -eEo pipefail

DOTFILES_DIR="$(pwd)"

# Canonical location hyprsimple manages itself from after install. Migrations,
# hyprsimple-refresh-config.sh and hyprsimple-update.sh all read from here, so
# updates work no matter where the repo was originally cloned.
export HYPRSIMPLE_PATH="$HOME/.local/share/hyprsimple"

echo "======================================"
echo "  Hyprsimple Installation Script"
echo "======================================"
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ======================================
#  Logging & error reporting
# ======================================
# Mirror everything to a log so a failed install can be diagnosed afterwards,
# and report the failing command instead of dying silently.

INSTALL_LOG="$HOME/.local/state/hyprsimple/install.log"
mkdir -p "$(dirname "$INSTALL_LOG")"
: >"$INSTALL_LOG"
exec > >(tee -a "$INSTALL_LOG") 2>&1

# Packages that could not be installed, reported together at the end rather
# than scrolling past in the middle of a long install.
FAILED_PACKAGES=()

debug_command() {
  if [[ -x "$HOME/.local/bin/hyprsimple-debug.sh" ]]; then
    echo "$HOME/.local/bin/hyprsimple-debug.sh"
  else
    echo "$DOTFILES_DIR/.local/bin/hyprsimple-debug.sh"
  fi
}

on_error() {
  local exit_code=$?
  local line=$1
  local failed_command=$BASH_COMMAND

  echo ""
  echo -e "${RED}======================================"
  echo "  Installation failed"
  echo -e "======================================${NC}"
  echo ""
  echo -e "${RED}install.sh line $line exited with status $exit_code:${NC}"
  echo "  $failed_command"
  echo ""
  echo "Full log: $INSTALL_LOG"
  echo ""
  echo "To report this, run:"
  echo ""
  echo "  $(debug_command)"
  echo ""
  echo "then attach the link it gives you to a new issue:"
  echo "https://github.com/rizukirr/hyprsimple/issues"
  echo ""
}

trap 'on_error $LINENO' ERR

# Check if running on Arch Linux
if [ ! -f /etc/arch-release ]; then
  echo -e "${RED}This script is designed for Arch Linux only!${NC}"
  exit 1
fi

# Check for AUR helper
if command -v yay &>/dev/null; then
  AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
  AUR_HELPER="paru"
else
  echo -e "${YELLOW}No AUR helper found. Installing yay...${NC}"
  sudo pacman -Syu
  sudo pacman -S --needed git base-devel
  if [[ ! -d "/tmp/yay" ]]; then
    git clone https://aur.archlinux.org/yay.git /tmp/yay
  fi

  cd /tmp/yay
  makepkg -si --noconfirm
  cd "$DOTFILES_DIR"
  AUR_HELPER="yay"
fi

echo -e "${GREEN}Using AUR helper: $AUR_HELPER${NC}"
echo ""

# ======================================
#  Hardware Detection Functions
# ======================================

detect_and_install_nvidia() {
  echo -e "${YELLOW}Detecting NVIDIA GPU...${NC}"

  # The predicate answers the yes or no, and the capture below supplies the
  # model string that the driver regexes need. Asking twice costs a second
  # lspci on NVIDIA machines only, which is nothing in a script that installs a
  # desktop, and it keeps one definition of what counts as an NVIDIA GPU.
  if ! bash "$DOTFILES_DIR/.local/bin/hyprsimple-hw-nvidia.sh"; then
    echo -e "${GREEN}No NVIDIA GPU detected, skipping${NC}"
    return 0
  fi
  NVIDIA="$(lspci | grep -i 'nvidia' || true)"

  echo -e "${GREEN}NVIDIA GPU detected: $NVIDIA${NC}"

  # Derive the kernel package base from the running kernel's modules dir
  # (works for stock Arch and custom kernels like linux-cachyos-lts).
  # Overridable so the suite can arrange both answers. A test that can only
  # ever see the kernel this machine is running has only tested one of them,
  # and on a CI runner with no pkgbase file at all it would test neither.
  MODULES_DIR="${HYPRSIMPLE_MODULES_DIR:-/usr/lib/modules}"
  KERNEL_BASE="$(cat "$MODULES_DIR/$(uname -r)/pkgbase" 2>/dev/null || true)"
  if [[ -z $KERNEL_BASE ]]; then
    echo -e "${YELLOW}Could not detect kernel package base; skipping NVIDIA driver install. Install '<kernel>-headers' and an NVIDIA driver manually: https://wiki.archlinux.org/title/NVIDIA${NC}"
    return 0
  fi
  KERNEL_HEADERS="${KERNEL_BASE}-headers"

  # Prefer a prebuilt kernel module if the repos ship one for this kernel
  # (e.g. CachyOS's linux-cachyos-nvidia-open) — avoids a DKMS rebuild and the
  # conflict between nvidia-open-dkms and the prebuilt NVIDIA-MODULE provider.
  NVIDIA_OPEN_PREBUILT=""
  if pacman -Si "${KERNEL_BASE}-nvidia-open" &>/dev/null; then
    NVIDIA_OPEN_PREBUILT="${KERNEL_BASE}-nvidia-open"
  fi

  # Turing+ (GTX 16xx, RTX 20xx-50xx, RTX Pro, Quadro RTX, datacenter)
  if echo "$NVIDIA" | grep -qE "GTX 16[0-9]{2}|RTX [2-5][0-9]{3}|RTX PRO [0-9]{4}|Quadro RTX|RTX A[0-9]{4}|A[1-9][0-9]{2}|H[1-9][0-9]{2}|T4|L[0-9]+"; then
    # The driver stack is kept apart from the additions, because a machine that
    # already has a driver must be given the second without the first.
    if [[ -n $NVIDIA_OPEN_PREBUILT ]]; then
      NVIDIA_DRIVER_PACKAGES=("$NVIDIA_OPEN_PREBUILT" nvidia-utils)
    else
      NVIDIA_DRIVER_PACKAGES=("$KERNEL_HEADERS" nvidia-open-dkms nvidia-utils)
    fi
    # prime-run lives in nvidia-prime, and FAQ.md's remedy for the Optimus boot
    # hang is written around having it. Nothing installed it.
    NVIDIA_EXTRA_PACKAGES=(libva-nvidia-driver nvidia-prime)
    NVIDIA_LIB32_PACKAGES=(lib32-nvidia-utils)
    NVIDIA_INSTALLER=(sudo pacman -S --noconfirm)
    GPU_ARCH="turing_plus"
  # Maxwell/Pascal/Volta (GTX 9xx/10xx, Quadro P/M, MX, Titan X/Xp/V)
  elif echo "$NVIDIA" | grep -qE "GTX (9[0-9]{2}|10[0-9]{2})|GT 10[0-9]{2}|Quadro [PM][0-9]{3,4}|Quadro GV100|MX *[0-9]+|Titan (X|Xp|V)|Tesla V100"; then
    NVIDIA_DRIVER_PACKAGES=("$KERNEL_HEADERS" nvidia-580xx-dkms nvidia-580xx-utils)
    NVIDIA_EXTRA_PACKAGES=(nvidia-prime)
    NVIDIA_LIB32_PACKAGES=(lib32-nvidia-580xx-utils)
    # The 580xx legacy series is not in any official Arch repository, so
    # installing it with `sudo pacman -S` could never have worked: every GTX
    # 9xx and 10xx machine on stock Arch got three "target not found" failures
    # and nothing else. Some derivatives do ship these in a repo, and an AUR
    # helper prefers the repo copy where one exists, so the helper is the right
    # installer on both.
    NVIDIA_INSTALLER=("$AUR_HELPER" -S --noconfirm)
    GPU_ARCH="maxwell_pascal_volta"
  else
    echo -e "${YELLOW}No compatible NVIDIA driver found. See: https://wiki.archlinux.org/title/NVIDIA${NC}"
    return 0
  fi

  # Distributions built on Arch often ship a working driver already: CachyOS
  # installs one whether or not the machine has an NVIDIA GPU. These packages do
  # not upgrade that, they collide with it. nvidia-580xx-dkms conflicts with
  # NVIDIA-MODULE, which every driver provides, and nvidia-580xx-utils conflicts
  # with nvidia-utils, so on such a machine the transaction cannot resolve at
  # all and --noconfirm turns that into a hard failure. --needed does not help,
  # because the collision is between different package names.
  #
  # A driver that is already there is the distribution's choice and probably
  # matches its kernel better than a guess from an lspci string does, so leave
  # it alone and install only what is additive.
  NVIDIA_PACKAGES=("${NVIDIA_EXTRA_PACKAGES[@]}")
  INSTALLED_MODULE="$(pacman -Qq NVIDIA-MODULE 2>/dev/null | head -1)"
  if [[ -n $INSTALLED_MODULE ]]; then
    echo -e "${GREEN}$INSTALLED_MODULE already provides the NVIDIA kernel module, so the driver stack is being left as it is. Installing only ${NVIDIA_EXTRA_PACKAGES[*]}.${NC}"
    echo -e "${YELLOW}If the GPU does not work after this, that driver is the one to change: remove $INSTALLED_MODULE, then re-run ./install.sh to get ${NVIDIA_DRIVER_PACKAGES[*]} instead.${NC}"
  else
    NVIDIA_PACKAGES=("${NVIDIA_DRIVER_PACKAGES[@]}" "${NVIDIA_PACKAGES[@]}")
    # 32-bit OpenGL, which is Steam and wine. Arch ships [multilib] commented
    # out and hyprsimple never edits pacman.conf, so on a stock install these
    # names do not resolve either. Upstream lists them unconditionally because
    # it ships its own pacman.conf with multilib turned on.
    if pacman-conf --repo-list 2>/dev/null | grep -qx multilib; then
      NVIDIA_PACKAGES+=("${NVIDIA_LIB32_PACKAGES[@]}")
    else
      echo -e "${YELLOW}[multilib] is not enabled, so ${NVIDIA_LIB32_PACKAGES[*]} is being skipped. Enable it in /etc/pacman.conf if you want 32-bit OpenGL for Steam or wine.${NC}"
    fi
  fi

  echo -e "${YELLOW}Installing NVIDIA packages: ${NVIDIA_PACKAGES[*]}${NC}"
  install_packages "${NVIDIA_INSTALLER[@]}" -- "${NVIDIA_PACKAGES[@]}"

  # install_packages collects failures into FAILED_PACKAGES and returns 0 either
  # way, so ask what actually landed. Writing the block below with no driver
  # present is worse than writing nothing: __GLX_VENDOR_LIBRARY_NAME=nvidia
  # points GLX at libGLX_nvidia.so.0, and with that file absent every OpenGL
  # application in the next session fails. nvidia-utils is the name to ask for
  # in every case: the legacy nvidia-580xx-utils provides it, and -Qq resolves
  # provides, so one question covers both generations and the driver a
  # distribution installed under some third name.
  if ! pacman -Qq nvidia-utils &>/dev/null; then
    echo -e "${YELLOW}No NVIDIA userspace driver is installed, so the NVIDIA environment variables and the initramfs rebuild are being skipped. Leaving them out keeps OpenGL working. Install the packages listed above by hand, then re-run ./install.sh.${NC}"
    return 0
  fi

  # On a hybrid machine the desktop is rendered by the integrated GPU:
  # detect_and_setup_multi_gpu below prefers Intel, then AMD, then NVIDIA, and
  # points AQ_DRM_DEVICES at whichever it picks. Exporting
  # __GLX_VENDOR_LIBRARY_NAME=nvidia on top of that sends every OpenGL
  # application to the discrete card anyway, so frames are rendered on the dGPU
  # and copied back to the iGPU that owns the display, and the dGPU never
  # powers down. Measured on an Optimus laptop with this block in place,
  # glxinfo reported "NVIDIA GeForce RTX 4050 Laptop GPU"; with the same three
  # variables unset, "Mesa Intel(R) Graphics (RPL-P)". Choosing the discrete
  # card per application is what prime-run is for.
  #
  # Upstream writes this block unconditionally and has no equivalent of
  # detect_and_setup_multi_gpu, so there it is consistent with the rest of the
  # configuration. Here it contradicted it.
  #
  # The same two lspci forms detect_and_setup_multi_gpu uses, so the two
  # functions cannot disagree about what this machine is.
  local other_gpu
  other_gpu=$(lspci -D | grep -iE "VGA.*Intel" | head -1 | cut -d' ' -f1 || true)
  [[ -z $other_gpu ]] &&
    other_gpu=$(lspci -D -d ::0300 | grep -i "AMD" | head -1 | cut -d' ' -f1 || true)

  if [[ -n $other_gpu ]]; then
    echo -e "${GREEN}An integrated GPU is present at $other_gpu, so it will drive the desktop and the NVIDIA environment variables are being left out. Setting them would push every OpenGL application onto the discrete card.${NC}"
    echo -e "${GREEN}Run a single program on the NVIDIA GPU with: prime-run <program>${NC}"
    echo -e "${GREEN}NVIDIA setup complete (arch: $GPU_ARCH, offload only)${NC}"
    return 0
  fi

  # Append NVIDIA env vars to uwsm/env
  if [[ $GPU_ARCH = "turing_plus" ]]; then
    cat >>"$HOME/.config/uwsm/env" <<'EOF'

# NVIDIA (Turing+ with GSP firmware) - auto-detected by installer
export NVD_BACKEND=direct
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
  elif [[ $GPU_ARCH = "maxwell_pascal_volta" ]]; then
    cat >>"$HOME/.config/uwsm/env" <<'EOF'

# NVIDIA (Maxwell/Pascal/Volta) - auto-detected by installer
export NVD_BACKEND=egl
export __GLX_VENDOR_LIBRARY_NAME=nvidia
EOF
  fi

  # Rebuild initramfs
  sudo mkinitcpio -P

  echo -e "${GREEN}NVIDIA setup complete (arch: $GPU_ARCH)${NC}"
}

detect_and_install_vulkan() {
  echo -e "${YELLOW}Detecting Vulkan-compatible GPUs...${NC}"

  declare -A VULKAN_DRIVERS=(
    [Intel]=vulkan-intel
    [AMD]=vulkan-radeon
    [Apple]=vulkan-asahi
  )

  VULKAN_PACKAGES=()
  for vendor in "${!VULKAN_DRIVERS[@]}"; do
    if lspci | grep -iE "(VGA|Display).*$vendor" > /dev/null 2>&1; then
      echo -e "${GREEN}Detected $vendor GPU, adding ${VULKAN_DRIVERS[$vendor]}${NC}"
      VULKAN_PACKAGES+=("${VULKAN_DRIVERS[$vendor]}")
    fi
  done

  if (( ${#VULKAN_PACKAGES[@]} > 0 )); then
    install_packages sudo pacman -S --noconfirm -- "${VULKAN_PACKAGES[@]}"
    echo -e "${GREEN}Vulkan drivers installed${NC}"
  else
    echo -e "${YELLOW}No Vulkan-compatible GPU detected${NC}"
  fi
}

detect_and_setup_multi_gpu() {
  echo -e "${YELLOW}Detecting GPUs...${NC}"

  # Detect GPUs (priority: Intel > AMD > NVIDIA)
  INTEL_PCI=$(lspci -D | grep -iE "VGA.*Intel" | head -1 | cut -d' ' -f1 || true)
  AMD_PCI=$(lspci -D -d ::0300 | grep -i "AMD" | head -1 | cut -d' ' -f1 || true)
  NVIDIA_PCI=$(lspci -D | grep -iE "VGA.*NVIDIA" | head -1 | cut -d' ' -f1 || true)

  GPU_SYMLINK=""
  GPU_VENDOR=""
  GPU_PCI=""

  if [[ -n $INTEL_PCI ]]; then
    GPU_VENDOR="Intel"
    GPU_PCI="$INTEL_PCI"
    GPU_SYMLINK="intel-gpu"
    echo -e "${GREEN}Intel GPU detected at: $GPU_PCI${NC}"
  elif [[ -n $AMD_PCI ]]; then
    GPU_VENDOR="AMD"
    GPU_PCI="$AMD_PCI"
    GPU_SYMLINK="amd-gpu"
    echo -e "${GREEN}AMD GPU detected at: $GPU_PCI${NC}"
  elif [[ -n $NVIDIA_PCI ]]; then
    GPU_VENDOR="NVIDIA"
    GPU_PCI="$NVIDIA_PCI"
    GPU_SYMLINK="nvidia-gpu"
    echo -e "${GREEN}NVIDIA GPU detected at: $GPU_PCI${NC}"
  else
    echo -e "${YELLOW}No GPU detected, skipping GPU setup${NC}"
    return 0
  fi

  # Create udev rule for consistent GPU device path
  UDEV_RULE_FILE="/etc/udev/rules.d/99-${GPU_SYMLINK}.rules"
  sudo tee "$UDEV_RULE_FILE" <<EOF >/dev/null
KERNEL=="card[0-9]*", KERNELS=="$GPU_PCI", SUBSYSTEM=="drm", SUBSYSTEMS=="pci", SYMLINK+="dri/$GPU_SYMLINK"
EOF

  echo -e "${GREEN}$GPU_VENDOR GPU udev rule created: /dev/dri/$GPU_SYMLINK -> $GPU_PCI${NC}"

  # Reload udev rules to create symlinks
  sudo udevadm control --reload
  sudo udevadm trigger

  # Write to env-hyprland (uwsm users should use this file per Hyprland docs)
  mkdir -p "$HOME/.config/uwsm"
  cat >>"$HOME/.config/uwsm/env-hyprland" <<EOF

# Primary GPU: $GPU_VENDOR (priority: Intel > AMD > NVIDIA)
export AQ_DRM_DEVICES="/dev/dri/$GPU_SYMLINK"
EOF

  echo -e "${GREEN}GPU setup complete ($GPU_VENDOR selected as primary)${NC}"
}

# Install packages. Bulk first, because one transaction resolves dependencies
# once. If the bulk install fails, retry one by one so we can name the packages
# that are actually broken instead of leaving the user with a half-configured
# desktop and no idea what went wrong, and so that one unresolvable name does
# not take the rest of its batch down with it.
#
# Usage: install_packages installer... -- package...
# The separator is needed because both halves are variadic. The caller supplies
# --noconfirm in the installer half when the site should run unattended, which
# is how packages.txt keeps prompting while the driver sites do not.
install_packages() {
  local installer=() saw_separator=0
  while (( $# > 0 )); do
    if [[ $1 == "--" ]]; then
      saw_separator=1
      shift
      break
    fi
    installer+=("$1")
    shift
  done

  # Without the separator every argument would be read as part of the installer,
  # leaving no packages, and the function would report success having installed
  # nothing.
  #
  # This exits rather than returning. A `return 1` is swallowed by any caller
  # that wraps the call in a condition, which turns a programming error into a
  # silently skipped install, and the ERR trap never fires there either. Since
  # the trap cannot report the location in that case, name it here.
  if (( ! saw_separator )); then
    echo -e "${RED}install.sh: install_packages was called without a -- separator${NC}" >&2
    echo -e "${RED}  at ${BASH_SOURCE[1]:-?} line ${BASH_LINENO[0]:-?}${NC}" >&2
    exit 1
  fi

  local packages=("$@")
  (( ${#packages[@]} == 0 )) && return 0

  if "${installer[@]}" --needed "${packages[@]}"; then
    return 0
  fi

  echo -e "${YELLOW}Bulk install failed. Retrying individually to identify the cause...${NC}"
  local pkg
  for pkg in "${packages[@]}"; do
    if ! "${installer[@]}" --needed --noconfirm "$pkg" >/dev/null 2>&1; then
      echo -e "${RED}Could not install: $pkg${NC}"
      FAILED_PACKAGES+=("$pkg")
    fi
  done
}

# The same thing, reading its package names from a file.
install_package_list() {
  local list_file="$1"
  shift
  local packages=()

  mapfile -t packages < <(grep -v '^\s*#' "$list_file" | grep -v '^\s*$')
  (( ${#packages[@]} == 0 )) && return 0

  install_packages "$@" -- "${packages[@]}"
}

# Install official packages
echo -e "${YELLOW}Installing official packages...${NC}"
if [ -f "$DOTFILES_DIR/packages.txt" ]; then
  sudo pacman -Syu
  install_package_list "$DOTFILES_DIR/packages.txt" sudo pacman -S
else
  echo -e "${RED}packages.txt not found!${NC}"
  exit 1
fi

# Install AUR packages
echo -e "${YELLOW}Installing AUR packages...${NC}"
if [ -f "$DOTFILES_DIR/aur-packages.txt" ]; then
  $AUR_HELPER -Syu || true
  install_package_list "$DOTFILES_DIR/aur-packages.txt" "$AUR_HELPER" -S
else
  echo -e "${YELLOW}aur-packages.txt not found, skipping AUR packages${NC}"
fi

# ======================================
#  Service & Hardware Setup
# ======================================

setup_bluetooth() {
  echo -e "${YELLOW}Setting up Bluetooth...${NC}"
  if command -v bluetoothctl &>/dev/null; then
    sudo systemctl enable bluetooth.service
    echo -e "${GREEN}Bluetooth enabled${NC}"
  fi
}

setup_network() {
  echo -e "${YELLOW}Setting up Network...${NC}"
  # Prevent boot hanging on network
  sudo systemctl disable systemd-networkd-wait-online.service 2>/dev/null

  # Both overridable so the suite can arrange a machine without resolved without
  # touching this one's DNS.
  local resolv_conf="${HYPRSIMPLE_RESOLV_CONF:-/etc/resolv.conf}"
  local resolved_stub="${HYPRSIMPLE_RESOLVED_STUB:-/run/systemd/resolve/stub-resolv.conf}"

  # This used to repoint /etc/resolv.conf at the stub unconditionally. Nothing
  # here installs or enables systemd-resolved, and when it is not running that
  # path does not exist, so the link dangled and the machine had no DNS at all:
  # not just afterwards, but for the rest of this script, which still has a
  # release tag to fetch and two packages to install. setup-dns.sh already
  # refuses to touch DNS when resolved is not running. This did the more
  # destructive version of the same thing with no check.
  if ! systemctl is-active --quiet systemd-resolved; then
    echo -e "${YELLOW}systemd-resolved is not running, enabling it...${NC}"
    sudo systemctl enable --now systemd-resolved 2>/dev/null || true
  fi

  # enable --now returns once the unit is active, which is not quite the same
  # moment the stub appears.
  local waited=0
  while [[ ! -e $resolved_stub ]] && (( waited < 30 )); do
    sleep 0.1
    waited=$((waited + 1))
  done

  if [[ -e $resolved_stub ]]; then
    sudo ln -sf "$resolved_stub" "$resolv_conf"
    echo -e "${GREEN}Network configured${NC}"
  else
    echo -e "${YELLOW}systemd-resolved is not running and could not be started, so $resolv_conf is being left alone. Pointing it at a stub that is not there would leave this machine with no DNS.${NC}"
  fi
}

setup_printer() {
  echo -e "${YELLOW}Setting up Printer support...${NC}"
  if pacman -Qi cups &>/dev/null; then
    sudo systemctl enable cups.service
    echo -e "${GREEN}Printer support enabled${NC}"
  fi
}

setup_firewall() {
  echo -e "${YELLOW}Setting up Firewall...${NC}"
  if command -v ufw &>/dev/null; then
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    # Allow LocalSend (LAN file sharing)
    sudo ufw allow 53317/tcp
    sudo ufw allow 53317/udp

    # `ufw enable` normally asks
    #
    #   Command may disrupt existing ssh connections. Proceed with operation (y|n)?
    #
    # and --force is exactly what skips that question. Skipping it is right for
    # a local install, where there is no ssh session to disrupt, and wrong when
    # this installer is itself running over one: "deny incoming" blocks the
    # next connection, so the machine becomes unreachable the moment the
    # session ends, and the one warning that would have said so was suppressed.
    #
    # SSH_CONNECTION is set by sshd for the session it serves, so this fires
    # only when the installer is running over the connection it would cut. A
    # local install is unchanged, and nobody's chosen posture is widened: the
    # port is opened only for a machine that is already being reached on it.
    if [[ -n ${SSH_CONNECTION-} ]]; then
      echo -e "${YELLOW}Installing over SSH, so ssh is kept reachable.${NC}"
      echo -e "${YELLOW}Close it later with: sudo ufw delete allow ssh${NC}"
      sudo ufw allow ssh
    fi

    sudo ufw --force enable
    echo -e "${GREEN}Firewall enabled (deny incoming, allow outgoing, LocalSend allowed)${NC}"
  else
    echo -e "${YELLOW}ufw not installed, skipping firewall${NC}"
  fi
}

setup_battery() {
  echo -e "${YELLOW}Detecting battery...${NC}"
  if bash "$DOTFILES_DIR/.local/bin/hyprsimple-hw-battery.sh"; then
    echo -e "${GREEN}Battery detected, setting balanced power profile${NC}"
    command -v powerprofilesctl &>/dev/null && powerprofilesctl set balanced
  else
    echo -e "${GREEN}No battery (desktop), setting performance profile${NC}"
    command -v powerprofilesctl &>/dev/null && powerprofilesctl set performance
  fi
}

echo -e "${YELLOW}Setting up services...${NC}"
setup_bluetooth || true
setup_network || true
setup_printer || true
setup_firewall || true
setup_battery || true
echo -e "${GREEN}Service setup complete${NC}"
echo ""

# ======================================
#  Self-install to the canonical path
# ======================================
# hyprsimple-update.sh and every migration read from $HYPRSIMPLE_PATH, so mirror
# this checkout there (including .git, so updates can pull).

# A directory with nothing in it is not somebody's data. A run that failed
# after creating the destination used to wedge every later run behind a message
# telling the user to move aside a directory this installer had made itself.
dir_is_empty() {
  local entry
  for entry in "$1"/* "$1"/.[!.]* "$1"/..?*; do
    [[ -e $entry || -L $entry ]] && return 1
  done
  return 0
}

install_to_canonical_path() {
  if [[ $DOTFILES_DIR = "$HYPRSIMPLE_PATH" ]]; then
    return 0
  fi

  # Asked before anything is touched. This used to sit in the middle of the
  # copy, after the rm -rf below, so answering "no" deleted the install that was
  # already there and then declined to replace it.
  if git -C "$DOTFILES_DIR" rev-parse HEAD &>/dev/null &&
    [[ -n $(git -C "$DOTFILES_DIR" status --porcelain) ]]; then
    echo -e "${YELLOW}Uncommitted changes in $DOTFILES_DIR will not be installed. Installing HEAD.${NC}"
    # Only ask when someone is there to answer. Under curl-pipe, stdin is the
    # script itself, so reading from it would consume the installer.
    if [[ -t 0 ]]; then
      read -rp "Continue and install HEAD? (y/N) " reply
      if [[ ! $reply =~ ^[Yy]$ ]]; then
        echo -e "${RED}Aborted. Commit or stash your changes, then run this again.${NC}"
        return 1
      fi
    fi
  fi

  if [[ -e $HYPRSIMPLE_PATH ]]; then
    if [[ ! -f "$HYPRSIMPLE_PATH/install.sh" ]] && ! dir_is_empty "$HYPRSIMPLE_PATH"; then
      echo -e "${RED}$HYPRSIMPLE_PATH exists but does not look like a hyprsimple checkout.${NC}"
      echo -e "${RED}Move it aside and re-run this installer.${NC}"
      return 1
    fi
    rm -rf "$HYPRSIMPLE_PATH"
  fi

  mkdir -p "$HYPRSIMPLE_PATH"

  # Copy only what git tracks. A bare `cp -a` of the source directory also
  # takes whatever .gitignore excludes: vendored checkouts, build output,
  # scratch files. git archive is an exact, self-maintaining list of tracked
  # content and preserves file modes and symlinks. .git is copied separately
  # because hyprsimple-update needs it to pull.
  # rev-parse HEAD rather than --git-dir: an initialised repository with no
  # commits passes --git-dir but makes `git archive HEAD` exit 128, which would
  # abort the installer under set -e. Testing HEAD covers both "not a repo" and
  # "no commits", and both divert to the plain copy below.
  if git -C "$DOTFILES_DIR" rev-parse HEAD &>/dev/null; then
    git -C "$DOTFILES_DIR" archive HEAD | tar -x -C "$HYPRSIMPLE_PATH"
    cp -a "$DOTFILES_DIR/.git" "$HYPRSIMPLE_PATH/.git"
  else
    # No index to consult, for example a downloaded tarball. Copy everything.
    cp -a "$DOTFILES_DIR/." "$HYPRSIMPLE_PATH/"
  fi

  echo -e "${GREEN}hyprsimple installed to $HYPRSIMPLE_PATH${NC}"
}

# New installs follow release tags rather than the tip of main, so a user who
# never passes an argument to hyprsimple-update only ever sees tagged versions.
# A source checkout on anything other than main is somebody testing a branch,
# and every failure here leaves the install on the branch it already had.
follow_latest_release() {
  [[ -d $HYPRSIMPLE_PATH/.git ]] || return 0

  local branch
  branch=$(git -C "$HYPRSIMPLE_PATH" symbolic-ref --quiet --short HEAD) || return 0
  [[ $branch == main ]] || return 0

  local tag
  tag=$(git -C "$HYPRSIMPLE_PATH" ls-remote --tags origin 2>/dev/null |
    sed 's|.*refs/tags/||; s|\^{}$||' | sort -u |
    awk '{ key = $0; sub(/^v/, "", key); print key "\t" $0 }' |
    sort -V | tail -1 | cut -f2) || return 0
  [[ -n $tag ]] || return 0

  # --depth 1 so this never undoes the history-shrinking migration. --force
  # because .git is copied from the source clone, which may carry a stale tag of
  # the same name, and git leaves such a tag alone while still exiting 0.
  git -C "$HYPRSIMPLE_PATH" fetch --quiet --force --depth 1 origin tag "$tag" 2>/dev/null || return 0
  git -C "$HYPRSIMPLE_PATH" checkout --quiet --detach "$tag" 2>/dev/null || return 0

  echo -e "${GREEN}Following releases, now on $tag.${NC}"
  echo "Run 'hyprsimple-update main' if you would rather track main."
}

echo ""
echo -e "${YELLOW}Installing hyprsimple to $HYPRSIMPLE_PATH...${NC}"
install_to_canonical_path
follow_latest_release

# A fresh install already ships every fix, so mark all migrations as done and
# let new users skip the entire history.
MIGRATION_STATE_DIR="$HOME/.local/state/hyprsimple/migrations"
mkdir -p "$MIGRATION_STATE_DIR/skipped"
for migration in "$HYPRSIMPLE_PATH/migrations"/*.sh; do
  [[ -f $migration ]] && touch "$MIGRATION_STATE_DIR/$(basename "$migration")"
done

# Copy configuration files
echo ""
echo -e "${YELLOW}Copying configuration files...${NC}"

# Move an existing target (file, dir, or symlink) aside before writing over it.
#
# This began with `rm -rf "$1.backup"`, which destroyed the thing the backup
# existed for. The first install moves your own config to <target>.backup. A
# second install, run months later to repair something, deleted that and put
# hyprsimple's own previous copy there instead. Demonstrated on a fixture:
# after two installs the original was gone, with zero copies left anywhere, and
# .backup held hyprsimple v1.
#
# The first backup is the one worth keeping, because it is the only one holding
# what was there before hyprsimple ever ran. Anything after it gets a
# timestamped name, so nothing is ever destroyed.
#
# hyprsimple-muslimtify.sh already learned this and says so in its own backup
# function. install.sh is where it costs the most.
backup_if_exists() {
  local target="$1" source="${2-}"
  [ -e "$target" ] || [ -L "$target" ] || return 0

  # Nothing worth preserving when what is there is already what is about to be
  # written. Without this, re-running the installer files a timestamped backup
  # of hyprsimple's own unchanged scripts every time.
  if [ -n "$source" ] && [ -f "$source" ] && [ -f "$target" ] && cmp -s "$source" "$target"; then
    return 0
  fi

  local backup="$target.backup"
  if [ -e "$backup" ] || [ -L "$backup" ]; then
    backup="$target.backup.$(date +%s)"
  fi

  echo -e "${YELLOW}Backing up existing $target to $backup${NC}"
  mv "$target" "$backup"
}

# Copy .config directories and files
for item in "$DOTFILES_DIR/.config"/*; do
  basename_item=$(basename "$item")

  target="$HOME/.config/$basename_item"
  backup_if_exists "$target" "$item"

  if [ -d "$item" ]; then
    cp -r "$item" "$target"
    echo -e "${GREEN}Copied:${NC} $basename_item"
  elif [ -f "$item" ]; then
    cp "$item" "$target"
    echo -e "${GREEN}Copied:${NC} $basename_item"
  fi
done

# Copy scripts
echo ""
echo -e "${YELLOW}Installing scripts to ~/.local/bin...${NC}"
mkdir -p "$HOME/.local/bin"

for script in "$DOTFILES_DIR/.local/bin"/*.sh "$DOTFILES_DIR/.local/bin"/*.fish; do
  if [ -f "$script" ]; then
    target="$HOME/.local/bin/$(basename "$script")"
    backup_if_exists "$target" "$script"
    cp "$script" "$target"
    chmod +x "$target"
    echo -e "${GREEN}Copied:${NC} $(basename "$script")"
  fi
done

# Copy .local/share assets
if [ -d "$DOTFILES_DIR/.local/share" ]; then
  echo ""
  echo -e "${YELLOW}Copying .local/share assets...${NC}"
  mkdir -p "$HOME/.local/share"
  for item in "$DOTFILES_DIR/.local/share"/*; do
    if [ -e "$item" ]; then
      basename_item=$(basename "$item")
      target="$HOME/.local/share/$basename_item"
      backup_if_exists "$target" "$item"
      cp -r "$item" "$target"
      echo -e "${GREEN}Copied:${NC} .local/share/$basename_item"
    fi
  done
fi

# ======================================
#  Hardware Auto-Detection
# ======================================
# NOTE: This runs AFTER config copying so GPU env vars
# appended to ~/.config/uwsm/env and env-hyprland are not overwritten.
echo ""
echo -e "${YELLOW}Running hardware detection...${NC}"

detect_and_install_nvidia || true
detect_and_install_vulkan || true
detect_and_setup_multi_gpu || true

echo -e "${GREEN}Hardware detection complete${NC}"
echo ""

# Enable and start services
echo ""
echo -e "${YELLOW}Enabling system services...${NC}"
systemctl --user enable --now pipewire pipewire-pulse wireplumber || true

# Enable battery monitor timer (if systemd files exist)
if [ -f "$HOME/.config/systemd/user/battery-monitor.timer" ]; then
  echo -e "${YELLOW}Enabling battery monitor timer...${NC}"
  systemctl --user daemon-reload
  # enable, not enable --now. The timer is wanted by graphical-session.target,
  # and the install runs from a TTY or another session where that target is not
  # up, so --now started a timer that would fire battery-monitor.sh with no
  # compositor: on a low battery that dims the panel and sends a notification
  # into a bus with no display, which is the case this ordering exists to
  # avoid. The session starts it.
  systemctl --user enable battery-monitor.timer
  echo -e "${GREEN}Battery monitor enabled${NC}"
fi

# Initialize Theme Manager (Default: Deep Sea)
DEFAULT_THEME="deep-sea"
echo ""
echo -e "${YELLOW}Initializing Theme Manager (Default: ${DEFAULT_THEME})...${NC}"
CACHE_DIR="$HOME/.cache"
mkdir -p "$CACHE_DIR"
mkdir -p "$HOME/.config/btop/themes"
mkdir -p "$HOME/.config/rofi"

# dunst reads drop-ins from dunstrc.d/ beside the base config. Symlinking the
# default rather than copying it is what lets hyprsimple-update deliver changes
# without a migration, the same guarantee package.path gives the lua config.
mkdir -p "$HOME/.config/dunst/dunstrc.d"
ln -sfn "$HYPRSIMPLE_PATH/default/dunst/10-hyprsimple.conf" "$HOME/.config/dunst/dunstrc.d/10-hyprsimple.conf"

# hyprlock, hypridle and xdph source their defaults through this link, so no
# config file has to hardcode an install path that HYPRSIMPLE_PATH can change.
ln -sfn "$HYPRSIMPLE_PATH/default/hypr" "$HOME/.config/hypr/hyprsimple"

# rofi resolves a relative @import against ~/.config/rofi no matter which file
# does the importing, so the stubs there reach their defaults through this link
# and the defaults keep reaching rofi-colors.rasi. Symlinking rather than
# copying is what lets hyprsimple-update deliver a rofi change without a
# migration, the same guarantee dunstrc.d and hypr/hyprsimple already give.
ln -sfn "$HYPRSIMPLE_PATH/default/rofi" "$HOME/.config/rofi/hyprsimple"

# There were two `ln -sfn "$THEME_DIR/rofi/<type>" ~/.config/rofi/<type>` lines
# here, meant to point the rofi directories at the active theme. They did
# neither thing. ~/.config/rofi/launcher is a real directory by then, copied
# from .config/rofi above, and `ln -s` given an existing directory writes the
# link inside it, so the result was ~/.config/rofi/launcher/launcher. And no
# theme has ever shipped a rofi/ directory, so the target did not exist either
# way and both links dangled from the moment they were made.
#
# theme-switcher.sh is what actually themes rofi: it writes images/ and patches
# style.rasi inside those real directories. Nothing was ever reading the links.

# Enable live wallpaper by default (theme-switcher reads this when writing hyprpaper.conf)
touch "$CACHE_DIR/live_wallpaper_enabled"

# Apply the default theme via theme-switcher.sh (skip runtime reloads — Hyprland isn't running yet)
THEME_SWITCHER_NO_RELOAD=1 bash "$HOME/.local/bin/theme-switcher.sh" "$DEFAULT_THEME"

# The cursor theme is persisted by theme-switcher.sh, which the line above just
# ran. It used to be done here instead, which meant it happened only at install
# time and only for whichever theme was the default, so switching themes later
# never updated it.
echo -e "${GREEN}Theme initialized${NC}"

mkdir -p ~/Videos
mkdir -p ~/Pictures

# Wire the shell-init script into the rc file for the user's actual login shell
echo -e "${YELLOW}Configuring shell integration...${NC}"
bash "$HOME/.local/bin/terminal.sh" || true

hyprctl reload || true
bash "$HOME/.local/bin/hyprsimple-restart-waybar.sh"
echo -e "${YELLOW}Starting waybar...${NC}"
sleep 3

# Set default volume to 65% for clean audio output combined with
# ~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf
pactl set-source-volume @DEFAULT_SOURCE@ 65%

systemctl --user enable --now hyprpaper.service || true
systemctl --user enable --now hyprpolkitagent.service || true
muslimtify daemon install || true
muslimtify daemon status || true
# thermald is Intel-only and pointless on AMD or on a desktop, so gate it
if bash "$DOTFILES_DIR/.local/bin/hyprsimple-hw-intel-laptop.sh"; then
  install_packages sudo pacman -S --noconfirm -- thermald
  sudo systemctl enable --now thermald || true
  echo -e "${GREEN}thermald enabled (Intel laptop detected)${NC}"
else
  echo -e "${YELLOW}Skipping thermald (not an Intel laptop)${NC}"
fi

echo ""
if (( ${#FAILED_PACKAGES[@]} > 0 )); then
  echo -e "${RED}======================================"
  echo "  Installed, but ${#FAILED_PACKAGES[@]} package(s) failed"
  echo -e "======================================${NC}"
  echo ""
  printf '  %s\n' "${FAILED_PACKAGES[@]}"
  echo ""
  echo "Features depending on these will not work. Try installing them by hand,"
  echo "then re-run ./install.sh. To report it:"
  echo ""
  echo "  $(debug_command)"
  echo ""
else
  echo -e "${GREEN}======================================"
  echo "  Installation Complete!"
  echo -e "======================================${NC}"
fi
echo ""
echo "Configuration files have been copied to your home directory."
echo "Edit files in ~/.config/ directly to customise; updates will not overwrite them."
echo ""
echo "Log saved to $INSTALL_LOG"
echo ""
echo "Next steps:"
echo "1. Log out and log back in to Hyprland"
echo "2. Customize ~/.config/hypr/monitors.lua for your setup"
echo "3. Update later with: hyprsimple-update"
echo ""

read -rp "Logout to take effect? (y/n) " logout
if [ "$logout" == "y" ]; then
  echo "Logging out..."
  # hyprsimple's own logout, the same one SUPER + X and the power menu run. It
  # closes windows and waits for them before stopping the session.
  #
  # This was `hyprctl dispatch exit`, which tears the compositor down at once.
  # A browser still flushing its profile is killed, which is the single thing
  # hypr-logout.sh was written to prevent, and the installer was the one place
  # still doing it. It is also the wrong call under uwsm, which wants its
  # session stopped rather than its compositor shot: `uwsm stop`, which
  # hypr-logout.sh ends with.
  #
  # An install run from a TTY has no session to leave. Saying so beats
  # hyprctl printing a socket error and the script exiting as though it worked.
  if pgrep -x Hyprland >/dev/null 2>&1; then
    "$HOME/.local/bin/hypr-logout.sh"
  else
    echo "No Hyprland session is running here, so there is nothing to log out of."
    echo "Log in to Hyprland to pick up the changes."
  fi
else
  echo "Exiting..."
  exit
fi
