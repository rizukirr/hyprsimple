#!/bin/bash
# Checks that every generated file a theme ships is delivered, and that both
# callers deliver through the same function.
#
# hyprsimple-update.sh re-rendered every theme when a template changed and then
# copied two of the eight generated files. A change to btop.theme.tpl or
# ghostty.conf.tpl was rendered, stamped as done, and never reached the program
# it was for until the user happened to switch theme. Never touches the real
# ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DELIVER="$REPO/.local/bin/hyprsimple-theme-deliver.sh"
SWITCHER="$REPO/.local/bin/theme-switcher.sh"
UPDATER="$REPO/.local/bin/hyprsimple-update.sh"
TEMPLATES="$REPO/.config/hypr/themes/templates"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}
for helper in pass fail check; do
  declare -F "$helper" >/dev/null || { printf 'not ok - helper %s missing\n' "$helper" >&2; exit 1; }
done

# ---- the set of templates, read out of the repository ----------------------
#
# Not a list kept here. A list would go stale the day a template is added,
# which is the failure this whole file is about.
mapfile -t tpl < <(find "$TEMPLATES" -maxdepth 1 -name '*.tpl' -printf '%f\n' | sed 's/\.tpl$//' | sort)
if (( ${#tpl[@]} < 6 )); then
  fail "found ${#tpl[@]} templates, which is too few to be right"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "found ${#tpl[@]} templates in the repository"

# ---- a theme whose generated directory holds one file per template ---------

H="$TMP/home"
mkdir -p "$H/.local/bin" "$H/.config/ghostty" "$H/.config/waybar" "$H/.config/rofi" "$H/.config/hypr"
THEME="$H/.config/hypr/themes/demo"
mkdir -p "$THEME/generated"
for name in "${tpl[@]}"; do
  printf 'MARKER-%s\n' "$name" >"$THEME/generated/$name"
done
printf 'theme = something-else\nfont-size = 12\n' >"$H/.config/ghostty/config"

HOME="$H" bash -c 'source "$1"; deliver_theme_configs "$2"' _ "$DELIVER" "$THEME" >/dev/null 2>&1

# Where each generated file is read from. This mapping is the contract, so it
# is spelled out, and the check below fails if a template has no entry.
declare -A target=(
  [hyprland-colors.lua]="$H/.config/hypr/theme-active.lua"
  [waybar-colors.css]="$H/.config/waybar/theme-active.css"
  [theme-clock.jsonc]="$H/.config/waybar/theme-clock.jsonc"
  [rofi-colors.rasi]="$H/.config/rofi/rofi-colors.rasi"
  [hyprlock.conf]="$H/.config/hypr/theme-hyprlock.conf"
  [dunst-colors]="$H/.config/dunst/dunstrc.d/90-theme.conf"
  [btop.theme]="$H/.config/btop/themes/current.theme"
  [ghostty.conf]="$H/.config/ghostty/config"
)

unmapped=()
undelivered=()
for name in "${tpl[@]}"; do
  dest="${target[$name]:-}"
  if [[ -z $dest ]]; then unmapped+=("$name"); continue; fi
  grep -qF "MARKER-$name" "$dest" 2>/dev/null || undelivered+=("$name")
done

unmapped_str=""; (( ${#unmapped[@]} > 0 )) && unmapped_str="$(printf '%s ' "${unmapped[@]}")"
check "every template in the repository has a known destination in this suite" "$unmapped_str" ""

undelivered_str=""; (( ${#undelivered[@]} > 0 )) && undelivered_str="$(printf '%s ' "${undelivered[@]}")"
check "and the delivery puts every one of them where its program reads it" "$undelivered_str" ""

# btop needs its config to name the theme, not just the file to exist.
check "btop's own config names the delivered theme" \
  "$(grep -c '^color_theme = "current"$' "$H/.config/btop/btop.conf" 2>/dev/null)" "1"

# The ghostty line the delivery replaces has to go, not sit above the new one.
check "and the ghostty theme line it replaced is gone" \
  "$(grep -c 'something-else' "$H/.config/ghostty/config")" "0"

# ---- both callers go through the one function ------------------------------
#
# The bug was two lists that disagreed. Checking the code here, not behaviour,
# because the thing to prevent is a second list appearing again.
code() { sed 's/#.*//' "$1"; }

check "theme-switcher.sh delivers through the shared function" \
  "$(code "$SWITCHER" | grep -c 'deliver_theme_configs')" "1"
check "and hyprsimple-update.sh through the same one" \
  "$(code "$UPDATER" | grep -c 'deliver_theme_configs')" "1"
check "and both source it" \
  "$(cat "$SWITCHER" "$UPDATER" | sed 's/#.*//' | grep -c 'hyprsimple-theme-deliver.sh')" "2"
check "with the copies that used to live in the updater gone" \
  "$(code "$UPDATER" | grep -cE 'cp "\$gen/')" "0"

# ---- the update restarts what it just rewrote ------------------------------
#
# waybar reads its stylesheet at startup and dunst its drop-ins at load, so a
# freshly written colour file is invisible until they are restarted. A theme
# switch has always done this; the update wrote the files and did not.
check "the update restarts waybar after delivering" \
  "$(code "$UPDATER" | grep -cE 'restart-waybar\.sh"? --if-running')" "1"
check "and dunst" \
  "$(code "$UPDATER" | grep -cE 'restart-dunst\.sh"? --if-running')" "1"
present=0
for s in hyprsimple-restart-waybar.sh hyprsimple-restart-dunst.sh; do
  [[ -f $REPO/.local/bin/$s ]] && present=$((present + 1))
done
check "and those two scripts exist to be called" "$present" "2"

# ---- delivery does not move the wallpaper ----------------------------------
#
# The update calls this function, and an update must not change the picture on
# the screen. That is the switch's job and it stayed with the switch.
check "the shared delivery leaves the wallpaper alone" \
  "$(code "$DELIVER" | grep -c 'current_wallpaper')" "0"
check "and the switcher still handles it" \
  "$(code "$SWITCHER" | grep -c 'current_wallpaper_path')" "1"

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
