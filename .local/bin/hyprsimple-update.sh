#!/bin/bash

# Update hyprsimple in place: pull the repo, refresh the helper scripts,
# install any newly required packages, then run pending migrations.
#
# Your ~/.config files are never overwritten here. When a default config has to
# change, the matching migration says so and uses hyprsimple-refresh-config.sh,
# which keeps a backup and shows you the diff.

set -eEo pipefail

export HYPRSIMPLE_PATH="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

trap 'echo -e "\n${RED}Update failed. Fix the error above and run hyprsimple-update again.${NC}"' ERR

if [[ ! -d $HYPRSIMPLE_PATH ]]; then
  echo -e "${RED}hyprsimple is not installed at $HYPRSIMPLE_PATH.${NC}"
  echo "Re-run ./install.sh from a fresh clone to set it up."
  exit 1
fi

# ---- Pull ----------------------------------------------------------------

if [[ -d $HYPRSIMPLE_PATH/.git ]]; then
  echo -e "${YELLOW}Pulling latest hyprsimple...${NC}"

  if [[ -n $(git -C "$HYPRSIMPLE_PATH" status --porcelain) ]]; then
    echo -e "${RED}$HYPRSIMPLE_PATH has local changes.${NC}"
    echo "Commit, stash, or discard them, then run hyprsimple-update again."
    exit 1
  fi

  branch=$(git -C "$HYPRSIMPLE_PATH" rev-parse --abbrev-ref HEAD)
  git -C "$HYPRSIMPLE_PATH" pull --ff-only origin "$branch"
else
  echo -e "${YELLOW}$HYPRSIMPLE_PATH is not a git checkout, skipping pull.${NC}"
fi

echo -e "${GREEN}Now on hyprsimple $(cat "$HYPRSIMPLE_PATH/version" 2>/dev/null || echo unknown)${NC}"

# ---- Helper scripts ------------------------------------------------------
# These are program code, not user config, so they are replaced wholesale.

echo -e "\n${YELLOW}Refreshing helper scripts in ~/.local/bin...${NC}"
mkdir -p "$HOME/.local/bin"

for script in "$HYPRSIMPLE_PATH/.local/bin"/*.sh "$HYPRSIMPLE_PATH/.local/bin"/*.fish; do
  [[ -f $script ]] || continue
  target="$HOME/.local/bin/$(basename "$script")"
  if ! cmp -s "$script" "$target"; then
    cp -f "$script" "$target"
    chmod +x "$target"
    echo -e "${GREEN}Updated:${NC} $(basename "$script")"
  fi
done

# ---- Packages ------------------------------------------------------------

install_missing_packages() {
  local list="$1" helper="$2"
  [[ -f $list ]] || return 0

  local missing=()
  while read -r pkg; do
    [[ -z $pkg || $pkg == \#* ]] && continue
    pacman -Qi "$pkg" &>/dev/null || missing+=("$pkg")
  done < <(grep -v '^\s*#' "$list")

  (( ${#missing[@]} == 0 )) && return 0

  echo -e "${YELLOW}Installing new packages: ${missing[*]}${NC}"
  $helper -S --needed --noconfirm "${missing[@]}" || true
}

if command -v yay &>/dev/null; then
  AUR_HELPER="yay"
elif command -v paru &>/dev/null; then
  AUR_HELPER="paru"
else
  AUR_HELPER=""
fi

echo -e "\n${YELLOW}Checking for newly required packages...${NC}"
install_missing_packages "$HYPRSIMPLE_PATH/packages.txt" "sudo pacman"
if [[ -n $AUR_HELPER ]]; then
  install_missing_packages "$HYPRSIMPLE_PATH/aur-packages.txt" "$AUR_HELPER"
fi

# ---- Migrations ----------------------------------------------------------

echo -e "\n${YELLOW}Running pending migrations...${NC}"
bash "$HOME/.local/bin/hyprsimple-migrate.sh"

# ---- Reload --------------------------------------------------------------

if pgrep -x Hyprland >/dev/null; then
  hyprctl reload >/dev/null || true
fi

echo -e "\n${GREEN}hyprsimple is up to date.${NC}"
