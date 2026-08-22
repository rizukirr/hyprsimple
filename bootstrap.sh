#!/bin/bash

# One-time, non-destructive upgrade for machines that installed hyprsimple
# before it could update itself.
#
#   curl -fsSL https://raw.githubusercontent.com/rizukirr/hyprsimple/main/bootstrap.sh | bash
#
# or, from an existing checkout:
#
#   ./bootstrap.sh
#
# Unlike install.sh this does NOT back up and replace your ~/.config. It only:
#   1. puts hyprsimple in its canonical location (~/.local/share/hyprsimple)
#   2. refreshes the helper scripts in ~/.local/bin
#   3. runs every migration, so the fixes you missed are applied surgically
#
# After this, use `hyprsimple-update` instead.

set -eEo pipefail

REPO_URL="${HYPRSIMPLE_REPO:-https://github.com/rizukirr/hyprsimple.git}"
REPO_REF="${HYPRSIMPLE_REF:-main}"
export HYPRSIMPLE_PATH="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "======================================"
echo "  hyprsimple bootstrap"
echo "======================================"
echo ""

if [[ ! -f /etc/arch-release ]]; then
  echo -e "${RED}hyprsimple targets Arch Linux only.${NC}"
  exit 1
fi

if (( EUID == 0 )); then
  echo -e "${RED}Run this as your normal user, not root.${NC}"
  exit 1
fi

# ---- Already bootstrapped? -----------------------------------------------

if [[ -d "$HYPRSIMPLE_PATH/.git" && -f "$HYPRSIMPLE_PATH/install.sh" ]]; then
  echo -e "${GREEN}hyprsimple is already set up at $HYPRSIMPLE_PATH.${NC}"
  echo -e "${YELLOW}Nothing to bootstrap — run hyprsimple-update instead.${NC}"
  exit 0
fi

# ---- Locate the source ---------------------------------------------------
# Prefer the checkout this script was run from; fall back to cloning.

SCRIPT_DIR=""
if [[ -n ${BASH_SOURCE[0]} && -f ${BASH_SOURCE[0]} ]]; then
  SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fi

if [[ -n $SCRIPT_DIR && -f "$SCRIPT_DIR/install.sh" && -d "$SCRIPT_DIR/migrations" ]]; then
  SOURCE_DIR="$SCRIPT_DIR"
  echo -e "${GREEN}Using the checkout at $SOURCE_DIR${NC}"
else
  SOURCE_DIR="$(mktemp -d)"
  trap 'rm -rf "$SOURCE_DIR"' EXIT
  echo -e "${YELLOW}Cloning hyprsimple ($REPO_REF)...${NC}"
  git clone --depth 1 --branch "$REPO_REF" "$REPO_URL" "$SOURCE_DIR" >/dev/null
fi

# ---- Canonical path ------------------------------------------------------

if [[ -e $HYPRSIMPLE_PATH ]]; then
  if [[ ! -f "$HYPRSIMPLE_PATH/install.sh" ]]; then
    echo -e "${RED}$HYPRSIMPLE_PATH exists but does not look like a hyprsimple checkout.${NC}"
    echo -e "${RED}Move it aside and run this again.${NC}"
    exit 1
  fi
  rm -rf "$HYPRSIMPLE_PATH"
fi

echo -e "\n${YELLOW}Installing hyprsimple to $HYPRSIMPLE_PATH...${NC}"
mkdir -p "$(dirname "$HYPRSIMPLE_PATH")"
cp -a "$SOURCE_DIR" "$HYPRSIMPLE_PATH"

# A shallow clone can't be pulled from later, so give it real history
if [[ -d "$HYPRSIMPLE_PATH/.git" ]]; then
  git -C "$HYPRSIMPLE_PATH" fetch --unshallow origin "$REPO_REF" >/dev/null 2>&1 || true
else
  echo -e "${YELLOW}Source was not a git checkout — hyprsimple-update will not be able to pull.${NC}"
fi
echo -e "${GREEN}Done${NC}"

# ---- Helper scripts ------------------------------------------------------

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

# ---- Migrations ----------------------------------------------------------
# Deliberately no state seeding here: this machine predates the migration
# system, so every migration should get a chance to run. They are written to be
# idempotent, so the ones whose fix you already have are no-ops.

echo -e "\n${YELLOW}Running migrations...${NC}"
bash "$HOME/.local/bin/hyprsimple-migrate.sh"

# ---- Done ----------------------------------------------------------------

if pgrep -x Hyprland >/dev/null; then
  hyprctl reload >/dev/null || true
fi

echo ""
echo -e "${GREEN}======================================"
echo "  Bootstrap complete!"
echo -e "======================================${NC}"
echo ""
echo "Your ~/.config was left alone except for the specific edits made by"
echo "migrations, each of which kept a backup if it replaced a whole file."
echo ""
echo "From now on, update with:"
echo ""
echo "  hyprsimple-update"
echo ""
echo "Open a new shell first so the new aliases are picked up."
