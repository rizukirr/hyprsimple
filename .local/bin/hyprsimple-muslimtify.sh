#!/bin/bash

# hyprsimple-muslimtify — add or remove the muslimtify integration.
#
# Usage:
#   hyprsimple-muslimtify.sh add      # install package + inject waybar module
#   hyprsimple-muslimtify.sh remove   # strip waybar module + uninstall package
#
# Edits ~/.config/waybar/config.jsonc and ~/.config/waybar/style.css.
# Backups are written next to the originals with a .bak suffix.

set -u

WAYBAR_CONFIG="$HOME/.config/waybar/config.jsonc"
WAYBAR_STYLE="$HOME/.config/waybar/style.css"

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

pick_aur_helper() {
  if command -v yay >/dev/null 2>&1; then echo yay
  elif command -v paru >/dev/null 2>&1; then echo paru
  else die "no AUR helper found (need yay or paru)"
  fi
}

reload_waybar() {
  "$HOME/.local/bin/hyprsimple-restart-waybar.sh"
  ok "waybar reloaded"
}

backup() {
  cp -f "$1" "$1.bak"
}

waybar_has_module() {
  grep -q '"custom/muslimtify"' "$WAYBAR_CONFIG"
}

pkg_installed() {
  pacman -Qi muslimtify >/dev/null 2>&1
}

# Returns the list of installed muslimtify-related packages (main + debug).
installed_pkgs() {
  local p list=()
  for p in muslimtify muslimtify-debug; do
    pacman -Qi "$p" >/dev/null 2>&1 && list+=("$p")
  done
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

  [[ -f "$WAYBAR_CONFIG" ]] || die "$WAYBAR_CONFIG not found"
  [[ -f "$WAYBAR_STYLE" ]] || die "$WAYBAR_STYLE not found"

  if waybar_has_module; then
    ok "waybar already has muslimtify module — skipping injection"
  else
    backup "$WAYBAR_CONFIG"

    # Insert into modules-left after "hyprland/workspaces"
    sed -i 's|"hyprland/workspaces"\(\s*\)\]|"hyprland/workspaces", "custom/muslimtify"\1]|' "$WAYBAR_CONFIG"
    sed -i 's|"hyprland/workspaces",|"hyprland/workspaces", "custom/muslimtify",|' "$WAYBAR_CONFIG"
    # Above two regexes collide if modules-left is just ["hyprland/workspaces"]; dedupe just in case:
    sed -i 's|"custom/muslimtify", "custom/muslimtify"|"custom/muslimtify"|g' "$WAYBAR_CONFIG"

    # Insert module definition before "custom/power"
    python3 - "$WAYBAR_CONFIG" <<'PY'
import sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
block = '''    "custom/muslimtify": {
        "exec": "~/.local/bin/waybar-muslimtify.sh",
        "return-type": "json",
        "interval": 30,
        "tooltip": true
    },
'''
anchor = '    "custom/power":'
if '"custom/muslimtify":' not in text and anchor in text:
    text = text.replace(anchor, block + anchor, 1)
    with open(path, 'w') as f:
        f.write(text)
PY
    ok "waybar config patched"
  fi

  if ! grep -q '#custom-muslimtify' "$WAYBAR_STYLE"; then
    backup "$WAYBAR_STYLE"
    cat >> "$WAYBAR_STYLE" <<'CSS'

#custom-muslimtify {
    background-color: @bg-widget;
    color: @warning;
    border: 1.5px solid alpha(@warning, 0.35);
    border-radius: 1.5rem 1.5rem 0.3rem 0.3rem;
    padding: 0.4rem 1.2rem;
    margin: 5px 0 0 1rem;
    text-shadow: 0 0 4px alpha(@warning, 0.25);
    box-shadow: inset 0 1px 0 alpha(@warning, 0.08), 0 1px 3px alpha(@bg-deep, 0.6);
    transition: all 300ms ease;
}

#custom-muslimtify:hover {
    background-color: alpha(@warning, 0.15);
    border-color: @warning;
    text-shadow: 0 0 10px alpha(@warning, 0.6);
    box-shadow: inset 0 1px 0 alpha(@warning, 0.15), 0 2px 8px alpha(@warning, 0.2);
}
CSS
    ok "waybar style patched"
  else
    ok "waybar style already has muslimtify rules — skipping"
  fi

  reload_waybar
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

  if [[ -f "$WAYBAR_CONFIG" ]] && waybar_has_module; then
    backup "$WAYBAR_CONFIG"
    # Strip the module reference from modules-left (handle both positions)
    sed -i 's|, *"custom/muslimtify"||g' "$WAYBAR_CONFIG"
    sed -i 's|"custom/muslimtify", *||g' "$WAYBAR_CONFIG"

    # Strip the module definition block ("custom/muslimtify": { ... },)
    python3 - "$WAYBAR_CONFIG" <<'PY'
import re, sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
# Match "custom/muslimtify": { ... }, including the trailing comma + newline
pattern = re.compile(r'[ \t]*"custom/muslimtify":\s*\{[^{}]*\},?\s*\n', re.DOTALL)
new_text = pattern.sub('', text)
with open(path, 'w') as f:
    f.write(new_text)
PY
    ok "waybar config cleaned"
  fi

  if [[ -f "$WAYBAR_STYLE" ]] && grep -q '#custom-muslimtify' "$WAYBAR_STYLE"; then
    backup "$WAYBAR_STYLE"
    python3 - "$WAYBAR_STYLE" <<'PY'
import re, sys
path = sys.argv[1]
with open(path) as f:
    text = f.read()
pattern = re.compile(r'\n*#custom-muslimtify[^{]*\{[^}]*\}\n*', re.DOTALL)
text = pattern.sub('\n', text)
with open(path, 'w') as f:
    f.write(text)
PY
    ok "waybar style cleaned"
  fi

  # NOTE: ~/.local/bin/waybar-muslimtify.sh is intentionally NOT removed.
  # Keeping it means `add` can re-enable cleanly without needing to recreate
  # the script from scratch. It's harmless when the daemon is uninstalled
  # (just produces no output).

  reload_waybar
  ok "muslimtify removed"
}

[[ $# -eq 1 ]] || usage
case "$1" in
  add) cmd_add ;;
  remove) cmd_remove ;;
  *) usage ;;
esac
