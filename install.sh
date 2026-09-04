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
  KERNEL_BASE="$(cat "/usr/lib/modules/$(uname -r)/pkgbase" 2>/dev/null || true)"
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
    if [[ -n $NVIDIA_OPEN_PREBUILT ]]; then
      NVIDIA_PACKAGES=("$NVIDIA_OPEN_PREBUILT" nvidia-utils libva-nvidia-driver)
    else
      NVIDIA_PACKAGES=("$KERNEL_HEADERS" nvidia-open-dkms nvidia-utils libva-nvidia-driver)
    fi
    GPU_ARCH="turing_plus"
  # Maxwell/Pascal/Volta (GTX 9xx/10xx, Quadro P/M, MX, Titan X/Xp/V)
  elif echo "$NVIDIA" | grep -qE "GTX (9[0-9]{2}|10[0-9]{2})|GT 10[0-9]{2}|Quadro [PM][0-9]{3,4}|Quadro GV100|MX *[0-9]+|Titan (X|Xp|V)|Tesla V100"; then
    NVIDIA_PACKAGES=("$KERNEL_HEADERS" nvidia-580xx-dkms nvidia-580xx-utils lib32-nvidia-580xx-utils)
    GPU_ARCH="maxwell_pascal_volta"
  else
    echo -e "${YELLOW}No compatible NVIDIA driver found. See: https://wiki.archlinux.org/title/NVIDIA${NC}"
    return 0
  fi

  echo -e "${YELLOW}Installing NVIDIA packages: ${NVIDIA_PACKAGES[*]}${NC}"
  install_packages sudo pacman -S --noconfirm -- "${NVIDIA_PACKAGES[@]}"

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
  # Symlink systemd-resolved
  sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
  echo -e "${GREEN}Network configured${NC}"
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

# Backup function: moves any existing target (file, dir, or symlink) to <target>.backup.
# Always copy-based; no symlink-install paths exist anymore.
backup_if_exists() {
  if [ -e "$1" ] || [ -L "$1" ]; then
    echo -e "${YELLOW}Backing up existing $1 to $1.backup${NC}"
    rm -rf "$1.backup"
    mv "$1" "$1.backup"
  fi
}

# Copy .config directories and files
for item in "$DOTFILES_DIR/.config"/*; do
  basename_item=$(basename "$item")

  target="$HOME/.config/$basename_item"
  backup_if_exists "$target"

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
    backup_if_exists "$target"
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
      backup_if_exists "$target"
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
  systemctl --user enable --now battery-monitor.timer
  echo -e "${GREEN}Battery monitor enabled${NC}"
fi

# Initialize Theme Manager (Default: Deep Sea)
DEFAULT_THEME="deep-sea"
echo ""
echo -e "${YELLOW}Initializing Theme Manager (Default: ${DEFAULT_THEME})...${NC}"
THEME_DIR="$HOME/.config/hypr/themes/$DEFAULT_THEME"
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

# One-time setup: symlink rofi launcher/powermenu dirs to the default theme
ln -sfn "$THEME_DIR/rofi/launcher" "$HOME/.config/rofi/launcher"
ln -sfn "$THEME_DIR/rofi/powermenu" "$HOME/.config/rofi/powermenu"

# Enable live wallpaper by default (theme-switcher reads this when writing hyprpaper.conf)
touch "$CACHE_DIR/live_wallpaper_enabled"

# Apply the default theme via theme-switcher.sh (skip runtime reloads — Hyprland isn't running yet)
THEME_SWITCHER_NO_RELOAD=1 bash "$HOME/.local/bin/theme-switcher.sh" "$DEFAULT_THEME"

# Install-only: persist cursor theme into uwsm/env so it's available on next login
if [[ -f "$THEME_DIR/cursor-theme" ]]; then
  CURSOR="$(cat "$THEME_DIR/cursor-theme")"
  echo "export XCURSOR_THEME=$CURSOR" >> "$HOME/.config/uwsm/env"
fi
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
echo "2. Customize ~/.config/hypr/monitors.conf for your setup"
echo "3. Update later with: hyprsimple-update"
echo ""

read -rp "Logout to take effect? (y/n) " logout
if [ "$logout" == "y" ]; then
    echo "Logging out..."
    hyprctl dispatch exit
else
    echo "Exiting..."
    exit
fi
