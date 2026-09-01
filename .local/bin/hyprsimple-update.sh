#!/bin/bash

# Update hyprsimple in place: pull the repo, refresh the helper scripts,
# install any newly required packages, then run pending migrations.
#
# Which commits you get is the "channel". A fresh install follows release tags.
# `hyprsimple-update <branch>` moves this install onto a branch and it stays
# there, `hyprsimple-update --stable` moves it back onto releases. The channel
# is remembered by git's own HEAD, so there is no state file to fall out of
# sync with the checkout.
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

usage() {
  cat <<'EOF'
Usage: hyprsimple-update [--stable | <branch>]

  (no argument)  Update within the channel this install already follows:
                 a release tag fetches the newest release, a branch pulls
                 that branch.
  --stable       Switch to the newest release tag, and stay on releases.
  <branch>       Switch to that branch of origin, and stay on it.

You only pass an argument when you want to change channel.
EOF
}

CHANNEL_ARG=""
case "${1-}" in
  -h | --help)
    usage
    exit 0
    ;;
  --stable)
    CHANNEL_ARG="--stable"
    ;;
  "") ;;
  -*)
    echo -e "${RED}Unknown option: $1${NC}" >&2
    usage >&2
    exit 1
    ;;
  *)
    CHANNEL_ARG="$1"
    ;;
esac

# The tag list cannot come from the local repository. The history-shrinking
# migration deletes every tag ref, and the fetch refspec only covers branches,
# so a shrunk install has no tags at all and never grows any on its own.
# Sorted on a v-stripped key so a tag named 0.2.3 and one named v0.2.4 order by
# their numbers. A plain `sort -V` puts every unprefixed tag below every
# prefixed one, which is only accidentally right while the newest tag has a v.
latest_release_tag() {
  git -C "$HYPRSIMPLE_PATH" ls-remote --tags origin |
    sed 's|.*refs/tags/||; s|\^{}$||' | sort -u |
    awk '{ key = $0; sub(/^v/, "", key); print key "\t" $0 }' |
    sort -V | tail -1 | cut -f2
}

if [[ ! -d $HYPRSIMPLE_PATH ]]; then
  echo -e "${RED}hyprsimple is not installed at $HYPRSIMPLE_PATH.${NC}"
  echo "Re-run ./install.sh from a fresh clone to set it up."
  exit 1
fi

# ---- Pull ----------------------------------------------------------------

# Recorded before the pull so the end of this run can name exactly which shipped
# configs changed, rather than comparing every file on every update.
PREV_COMMIT=""
[[ -d $HYPRSIMPLE_PATH/.git ]] && PREV_COMMIT=$(git -C "$HYPRSIMPLE_PATH" rev-parse HEAD 2>/dev/null)

if [[ -d $HYPRSIMPLE_PATH/.git ]]; then
  echo -e "${YELLOW}Pulling latest hyprsimple...${NC}"

  if [[ -n $(git -C "$HYPRSIMPLE_PATH" status --porcelain) ]]; then
    echo -e "${RED}$HYPRSIMPLE_PATH has local changes.${NC}"
    echo "Commit, stash, or discard them, then run hyprsimple-update again."
    exit 1
  fi

  # symbolic-ref fails exactly when HEAD is detached, and HEAD is detached
  # exactly when this install is sitting on a release tag.
  current_branch=$(git -C "$HYPRSIMPLE_PATH" symbolic-ref --quiet --short HEAD) || current_branch=""

  target="$CHANNEL_ARG"
  if [[ -z $target ]]; then
    if [[ -n $current_branch ]]; then target="$current_branch"; else target="--stable"; fi
  fi

  if [[ $target == "--stable" ]]; then
    tag=$(latest_release_tag) || {
      echo -e "${RED}Could not reach origin to list releases.${NC}"
      exit 1
    }
    if [[ -z $tag ]]; then
      echo -e "${RED}origin has no release tags. Use: hyprsimple-update main${NC}"
      exit 1
    fi
    if [[ -n $current_branch ]]; then
      echo -e "${YELLOW}Leaving branch $current_branch for releases.${NC}"
    fi
    # --depth 1: an install that was shrunk to a shallow clone must stay one, or
    # the 165 MB that migration reclaimed comes straight back.
    #
    # --force: a tag that already exists locally is never updated without it.
    # git prints "! [rejected] (would clobber existing tag)" and still exits 0,
    # so a re-pointed release would leave the install on the old commit while
    # this script reported success.
    git -C "$HYPRSIMPLE_PATH" fetch --quiet --force --depth 1 origin tag "$tag" || {
      echo -e "${RED}Could not fetch $tag from origin.${NC}"
      exit 1
    }
    git -C "$HYPRSIMPLE_PATH" checkout --quiet --detach "$tag"
    CHANNEL_LABEL="release $tag"
  else
    # No --depth here, unlike the tag path. On a shallow clone --depth 1 moves
    # the shallow boundary to the new tip, which disconnects the commit this
    # install is on and turns the fast-forward below into "refusing to merge
    # unrelated histories". A plain fetch keeps the boundary and stays shallow.
    if ! git -C "$HYPRSIMPLE_PATH" fetch --quiet origin "$target"; then
      echo -e "${RED}origin has no branch called '$target'.${NC}"
      exit 1
    fi
    if [[ $target == "$current_branch" ]]; then
      # Staying put keeps today's guarantee that an update never discards a
      # local commit.
      git -C "$HYPRSIMPLE_PATH" merge --quiet --ff-only FETCH_HEAD
    else
      # Changing channel is an explicit instruction, so this one force-moves.
      echo -e "${YELLOW}Switching from ${current_branch:-releases} to branch $target.${NC}"
      git -C "$HYPRSIMPLE_PATH" checkout --quiet -B "$target" FETCH_HEAD
    fi
    CHANNEL_LABEL="branch $target"
  fi
else
  echo -e "${YELLOW}$HYPRSIMPLE_PATH is not a git checkout, skipping pull.${NC}"
fi

echo -e "${GREEN}Now on hyprsimple $(cat "$HYPRSIMPLE_PATH/version" 2>/dev/null || echo unknown)${CHANNEL_LABEL:+ (${CHANNEL_LABEL})}${NC}"

# ---- Helper scripts ------------------------------------------------------
# These are program code, not user config, so they are replaced wholesale.

echo -e "\n${YELLOW}Refreshing helper scripts in ~/.local/bin...${NC}"
mkdir -p "$HOME/.local/bin"

for script in "$HYPRSIMPLE_PATH/.local/bin"/*.sh "$HYPRSIMPLE_PATH/.local/bin"/*.fish; do
  [[ -f $script ]] || continue
  target="$HOME/.local/bin/$(basename "$script")"
  if ! cmp -s "$script" "$target"; then
    # Write beside the target and rename, rather than cp -f over it.
    #
    # One of these scripts is this one. cp -f rewrites the same inode, and bash
    # reads a script incrementally by byte offset, so the running shell would
    # resume at its old offset inside the new, longer file and land mid-word.
    # That is a real failure seen in the wild: "line 61: he: command not found",
    # after which the pull had already happened but the migrations never ran.
    #
    # A rename gives the new content a different inode. The running shell keeps
    # reading the old one through the descriptor it already holds, finishes
    # normally, and the next run picks up the new version.
    cp -f "$script" "$target.new"
    chmod +x "$target.new"
    mv -f "$target.new" "$target"
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

# ---- Configs this update changed that you still hold your own copy of ----
#
# Some configs cannot be delivered automatically. starship.toml, yazi.toml and
# hyprsunset.conf are TOML and wlogout/layout is a stream of JSON objects, and
# none of those formats has an include directive, so there is no equivalent of
# the rofi stubs or the dunst drop-in for them.
#
# hyprsimple-refresh-config.sh has always been able to update one, but nothing
# ever said that it needed updating, so the command existed and was never run.
# This closes that, and it is deliberately driven by what this pull actually
# changed rather than by comparing everything: a user who edited a file on
# purpose is not nagged on every update, only when hyprsimple touches the same
# file. Migrations run first, so anything already handled is not mentioned.

if [[ -n $PREV_COMMIT ]] && [[ $PREV_COMMIT != "$(git -C "$HYPRSIMPLE_PATH" rev-parse HEAD 2>/dev/null)" ]]; then
  drifted=()
  while IFS= read -r rel; do
    [[ -n $rel ]] || continue
    shipped="$HYPRSIMPLE_PATH/$rel"
    user="$HOME/.config/${rel#.config/}"
    # Absent means the user never had it, and a symlink means something else
    # already manages it. Neither is drift.
    [[ -f $shipped && -f $user && ! -L $user ]] || continue
    cmp -s "$shipped" "$user" || drifted+=("${rel#.config/}")
  done < <(git -C "$HYPRSIMPLE_PATH" diff --name-only "$PREV_COMMIT" HEAD -- .config/ 2>/dev/null)

  if [[ ${#drifted[@]} -gt 0 ]]; then
    echo -e "\n${YELLOW}This update changed configs you have your own version of:${NC}"
    for rel in "${drifted[@]}"; do
      echo "  hyprsimple-refresh-config.sh $rel"
    done
    echo "Each one backs your version up and shows the diff. Nothing is deleted."
  fi
fi

# ---- Reload --------------------------------------------------------------

if pgrep -x Hyprland >/dev/null; then
  hyprctl reload >/dev/null || true
fi

echo -e "\n${GREEN}hyprsimple is up to date.${NC}"
