#!/bin/bash

# hyprsimple-muslimtify — add or remove the muslimtify integration.
#
# Usage:
#   hyprsimple-muslimtify.sh add      # install the package and its daemon
#   hyprsimple-muslimtify.sh remove   # remove the daemon and the package
#
# The bar shows prayer times on its own whenever muslimtify is installed, and
# hides them when it is not. It looks for muslimtify once, at startup, so both
# commands end by restarting the bar.

set -u

RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
NC=$'\033[0m'

die() { echo -e "${RED}error:${NC} $*" >&2; exit 1; }
info() { echo -e "${YELLOW}==>${NC} $*"; }
ok() { echo -e "${GREEN}✓${NC} $*"; }

usage() {
  echo "Usage: $(basename "$0") add|remove"
  exit 1
}

# Whichever helper is installed. This read yay first, so a paru machine
# installed muslimtify through yay the moment yay was present for any other
# reason. Shared with install.sh and hyprsimple-update.sh now.
AUR_DETECT="$HOME/.local/bin/hyprsimple-aur-helper.sh"
if [[ -r $AUR_DETECT ]]; then
  # shellcheck source=/dev/null
  source "$AUR_DETECT"
else
  die "missing helper: hyprsimple-aur-helper.sh. Run hyprsimple-update."
fi

pick_aur_helper() {
  local helper
  # aur_helper says on stderr which name it could not find, so the message
  # here only has to cover the case where nothing is installed at all.
  helper="$(aur_helper)" || die "no AUR helper found (need paru or yay)"
  printf '%s\n' "$helper"
}

reload_bar() {
  "$HOME/.local/bin/hyprsimple-restart-bar.sh" --if-running
  ok "bar restarted"
}

pkg_installed() {
  pacman -Qi muslimtify >/dev/null 2>&1
}

# Returns the list of installed muslimtify-related packages (main + debug), or
# nothing at all when none are installed.
#
# The guard matters. `printf '%s\n'` with no arguments still prints one empty
# line, so an empty list reached mapfile as an array of length one holding "",
# the caller's `(( ${#pkgs[@]} > 0 ))` was true, and remove tried to uninstall a
# package with no name.
installed_pkgs() {
  local p list=()
  for p in muslimtify muslimtify-debug; do
    pacman -Qi "$p" >/dev/null 2>&1 && list+=("$p")
  done
  (( ${#list[@]} > 0 )) || return 0
  printf '%s\n' "${list[@]}"
}

cmd_add() {
  if pkg_installed; then
    ok "muslimtify package already installed"
  else
    info "installing muslimtify via $(pick_aur_helper)"
    "$(pick_aur_helper)" -S --noconfirm muslimtify || die "package install failed"
  fi

  info "registering muslimtify daemon"
  muslimtify daemon install || true
  muslimtify daemon status || true

  reload_bar
  ok "muslimtify added"
}

cmd_remove() {
  if command -v muslimtify >/dev/null 2>&1; then
    info "unregistering muslimtify daemon (systemd units)"
    muslimtify daemon uninstall 2>/dev/null || true
  fi

  mapfile -t pkgs < <(installed_pkgs)
  if (( ${#pkgs[@]} > 0 )); then
    info "uninstalling ${pkgs[*]} via $(pick_aur_helper)"
    "$(pick_aur_helper)" -Rns --noconfirm "${pkgs[@]}" || die "package removal failed"
  elif command -v muslimtify >/dev/null 2>&1; then
    bin_path="$(command -v muslimtify)"
    echo -e "${YELLOW}note:${NC} muslimtify binary at $bin_path was not installed via pacman."
    echo -e "      remove it manually if you want full cleanup (e.g. sudo rm $bin_path)."
  else
    ok "muslimtify already absent"
  fi

  systemctl --user daemon-reload 2>/dev/null || true

  reload_bar
  ok "muslimtify removed"
}

[[ $# -eq 1 ]] || usage
case "$1" in
  add) cmd_add ;;
  remove) cmd_remove ;;
  *) usage ;;
esac
