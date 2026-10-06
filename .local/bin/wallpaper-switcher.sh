#!/bin/bash

# This one line cannot use require_helper, so it carries the check itself.
source "$HOME/.local/bin/hyprsimple-require.sh" 2>/dev/null || {
  echo "hyprsimple: missing helper: hyprsimple-require.sh. Run hyprsimple-update." >&2
  command -v notify-send >/dev/null &&
    notify-send -u critical "hyprsimple" "Missing helper: hyprsimple-require.sh. Run hyprsimple-update."
  exit 1
}
require_helper hypr-helpers.sh

# Switch wallpaper within the current theme
# Usage: wallpaper-switcher.sh [pick|add|next|apply <file>]
#   pick  - choose from the bar's wallpaper picker (default)
#   add   - choose an image file, copy it into the theme and show it
#   next  - cycle to next wallpaper, for a bind of your own
#   apply - show the given wallpaper, which is what the picker runs

CACHE_DIR="$HOME/.cache"
# Track the actual wallpaper source path in a state file.
#
# No readlink fallback on current_wallpaper. There used to be one, and it could
# never fire: every writer of that file, here and in theme-switcher.sh and
# live-wallpaper-toggle.sh, copies the picture rather than linking to it, so
# readlink -f returned the copy's own path and BG_DIR came out as
# $HOME/backgrounds. It read as a safety net and was a dead branch.
CURRENT=$(cat "$CACHE_DIR/current_wallpaper_path" 2>/dev/null)
THEME_DIR=$(dirname "$(dirname "$CURRENT")" 2>/dev/null)
BG_DIR="$THEME_DIR/backgrounds"

if [[ ! -d $BG_DIR ]]; then
  notify-send "Wallpaper" "No backgrounds folder found for current theme"
  exit 1
fi

# Get all wallpapers sorted
# -L, so a wallpaper that is a symlink counts. Without it every theme whose
# backgrounds hold a link had no wallpaper at all: find -type f does not match
# a symlink, and the themes added with the colorscheme catalogue share one
# image that way until they have their own.
# jpg, jpeg, png and webp, matched without regard to case, and the same set in
# every script that looks for a wallpaper. The switchers took *.png and *.jpg
# only, so a .jpeg wallpaper appeared in the picker and then could not be set,
# and a .webp one was invisible everywhere. hyprpaper links libwebp and reads
# all four.
mapfile -t WALLPAPERS < <(find -L "$BG_DIR" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) | sort)

MODE="${1:-pick}"

if [[ $MODE == "pick" ]]; then
  # The picker is a panel of the bar, which runs this again as
  # `wallpaper-switcher.sh apply <file>` with the wallpaper that was picked.
  #
  # Opened however many wallpapers the theme has. It used to stop here with
  # "Only one wallpaper in this theme", which was true while a picker could
  # only choose. It is also where one is added, and where cycling is switched
  # on, and a theme with one wallpaper is the one that most needs the first.
  exec qs -p "${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/default/quickshell" ipc call bar toggle wallpapers
elif [[ $MODE == "apply" ]]; then
  SELECTED="$2"
elif [[ $MODE == "add" ]]; then
  if ! command -v zenity >/dev/null 2>&1; then
    notify-send -u critical "Wallpaper" "zenity is missing, so there is nothing to choose a file with. Run hyprsimple-update."
    exit 1
  fi
  # Both cases of each ending, since zenity's patterns tell them apart and a
  # camera writes IMG_0001.JPG.
  CHOSEN=$(zenity --file-selection --title="Add a wallpaper" \
    --file-filter="Images | *.jpg *.jpeg *.png *.webp *.JPG *.JPEG *.PNG *.WEBP" 2>/dev/null) || exit 0
  [[ -n $CHOSEN ]] || exit 0

  # The filter is a suggestion: the dialog lets a path be typed. The ending is
  # what every script that looks for a wallpaper goes by, so one without it
  # would be copied in and then never listed.
  case "${CHOSEN,,}" in
    *.jpg | *.jpeg | *.png | *.webp) ;;
    *)
      notify-send "Wallpaper" "Not added: $(basename "$CHOSEN") is not a jpg, jpeg, png or webp"
      exit 1
      ;;
  esac
  if [[ ! -f $CHOSEN ]]; then
    notify-send "Wallpaper" "File not found: $CHOSEN"
    exit 1
  fi

  NAME=$(basename "$CHOSEN")
  SELECTED="$BG_DIR/$NAME"
  # A file already there under that name is kept. The same picture chosen twice
  # is not copied twice, and a different one gets a number.
  if [[ -e $SELECTED ]] && ! cmp -s "$CHOSEN" "$SELECTED"; then
    STEM="${NAME%.*}"
    EXT="${NAME##*.}"
    N=2
    while [[ -e "$BG_DIR/$STEM-$N.$EXT" ]]; do N=$((N + 1)); done
    SELECTED="$BG_DIR/$STEM-$N.$EXT"
  fi
  if [[ ! -e $SELECTED ]] && ! cp "$CHOSEN" "$SELECTED"; then
    notify-send -u critical "Wallpaper" "Could not copy $NAME into $BG_DIR"
    exit 1
  fi
elif [[ $MODE == "next" ]]; then
  if (( ${#WALLPAPERS[@]} == 0 )); then
    notify-send "Wallpaper" "No wallpapers found"
    exit 1
  fi

  if (( ${#WALLPAPERS[@]} == 1 )); then
    notify-send "Wallpaper" "Only one wallpaper in this theme"
    exit 0
  fi

  # Find current index and cycle to next
  NEXT=0
  for i in "${!WALLPAPERS[@]}"; do
    if [[ "${WALLPAPERS[$i]}" == "$CURRENT" ]]; then
      NEXT=$(( (i + 1) % ${#WALLPAPERS[@]} ))
      break
    fi
  done
  SELECTED="${WALLPAPERS[$NEXT]}"
else
  echo "Usage: wallpaper-switcher.sh [pick|add|next|apply <file>]" >&2
  exit 1
fi

if [[ ! -f $SELECTED ]]; then
  notify-send "Wallpaper" "File not found: $SELECTED"
  exit 1
fi

# Apply wallpaper. The copies are what the lock screen and the next login read.
rm -f "$CACHE_DIR/current_wallpaper" "$CACHE_DIR/current_lockscreen.png"
cp "$SELECTED" "$CACHE_DIR/current_wallpaper"
cp "$SELECTED" "$CACHE_DIR/current_lockscreen.png"
echo "$SELECTED" > "$CACHE_DIR/current_wallpaper_path"

# Disable live wallpaper mode (manual pick overrides cycling)
rm -f "$CACHE_DIR/live_wallpaper_enabled"
write_hyprpaper_conf "$HOME/.cache/current_wallpaper"

show_wallpaper "$SELECTED"

notify-send "Wallpaper" "$(basename "$SELECTED")" -i "$SELECTED"
