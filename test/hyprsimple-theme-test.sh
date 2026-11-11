#!/bin/bash
# The hyprsimple theme, made from Hypri's colours, is the default for new
# installs and reaches existing ones through a migration. This checks both
# halves: that install.sh and hyprpaper.conf name it, and that the migration
# adds it where it is missing without touching anything else.
#
# Every run of the migration is against a throwaway HOME, so the machine
# running this suite is never edited.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

THEME="$REPO/.config/hypr/themes/hyprsimple"
MIGRATION=$(grep -l "Add the hyprsimple theme" "$REPO"/migrations/*.sh | head -1)

# --- the theme itself -----------------------------------------------------------

check "the theme ships with its colours" "$([[ -f $THEME/colors.toml ]] && echo yes || echo no)" "yes"
check "and its three wallpapers" "$(find "$THEME/backgrounds" -maxdepth 1 -type f | wc -l | tr -d ' ')" "3"
check "and is dark, so it carries no light.mode" "$([[ -e $THEME/light.mode ]] && echo yes || echo no)" "no"
check "its background is Hypri's base colour" "$(grep -c '^background = "#0B0F19"$' "$THEME/colors.toml")" "1"
check "and its accent the cyan of her headphones" "$(grep -c '^accent = "#38BDF8"$' "$THEME/colors.toml")" "1"

# --- it is the default ------------------------------------------------------------

check "install.sh applies it on a fresh install" \
  "$(sed -n 's/^DEFAULT_THEME="\(.*\)"$/\1/p' "$REPO/install.sh")" "hyprsimple"
check "and the shipped hyprpaper.conf points at its wallpapers" \
  "$(grep -c 'path = ~/.config/hypr/themes/hyprsimple/backgrounds' "$REPO/.config/hypr/hyprpaper.conf")" "1"

# --- the migration ------------------------------------------------------------------

if [[ -z $MIGRATION ]]; then
  fail "no migration adds the hyprsimple theme"
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
pass "found the migration, $(basename "$MIGRATION")"

check "its first line says what it does" \
  "$(head -1 "$MIGRATION")" 'echo "Add the hyprsimple theme, made from Hypri'"'"'s colours"'

run() { HOME="$1" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/out" 2>&1; }

# A home with themes but not this one, using another theme.
h="$TMP/home"
mkdir -p "$h/.config/hypr/themes/nord"
echo 'mine' >"$h/.config/hypr/themes/nord/colors.toml"
run "$h"
check "it succeeds" "$?" "0"
check "and adds the theme" \
  "$(cmp -s "$THEME/colors.toml" "$h/.config/hypr/themes/hyprsimple/colors.toml" && echo same || echo different)" "same"
check "with its wallpapers" \
  "$(find "$h/.config/hypr/themes/hyprsimple/backgrounds" -maxdepth 1 -type f | wc -l | tr -d ' ')" "3"
check "and its icon theme" \
  "$(cat "$h/.config/hypr/themes/hyprsimple/icon-theme")" "$(cat "$THEME/icon-theme")"
check "leaving the other themes alone" "$(cat "$h/.config/hypr/themes/nord/colors.toml")" "mine"
check "and leaving no partial copy behind" \
  "$([[ -e $h/.config/hypr/themes/.hyprsimple.partial ]] && echo left || echo gone)" "gone"
check "and says what to press to try it" "$(grep -c 'SUPER + SHIFT + T' "$TMP/out")" "1"

before=$(find "$h" -type f -exec md5sum {} + | sort)
run "$h"
check "running it again succeeds" "$?" "0"
check "and changes nothing" "$(find "$h" -type f -exec md5sum {} + | sort)" "$before"

# Someone who already made a theme of their own under the same name keeps it.
h="$TMP/own"
mkdir -p "$h/.config/hypr/themes/hyprsimple"
echo 'my own' >"$h/.config/hypr/themes/hyprsimple/colors.toml"
run "$h"
check "a theme of your own named hyprsimple is kept" \
  "$(cat "$h/.config/hypr/themes/hyprsimple/colors.toml")" "my own"
check "and named in what it prints" "$(grep -c 'left as it is' "$TMP/out")" "1"

# A run cut short after the copy and before the move leaves a partial copy.
h="$TMP/partial"
mkdir -p "$h/.config/hypr/themes/.hyprsimple.partial"
echo 'half' >"$h/.config/hypr/themes/.hyprsimple.partial/colors.toml"
run "$h"
check "after an interrupted run, the next one still adds the theme" \
  "$(cmp -s "$THEME/colors.toml" "$h/.config/hypr/themes/hyprsimple/colors.toml" && echo same || echo different)" "same"
check "and clears the partial copy" \
  "$([[ -e $h/.config/hypr/themes/.hyprsimple.partial ]] && echo left || echo gone)" "gone"

# Nothing to add to.
h="$TMP/bare"
mkdir -p "$h"
run "$h"
check "a home with no themes directory succeeds" "$?" "0"
check "and is left alone" "$([[ -e $h/.config/hypr/themes ]] && echo created || echo absent)" "absent"

# An install too old to ship the theme.
h="$TMP/old"
mkdir -p "$h/.config/hypr/themes" "$TMP/oldrepo"
HOME="$h" HYPRSIMPLE_PATH="$TMP/oldrepo" bash "$MIGRATION" >"$TMP/out" 2>&1
check "an install that does not ship the theme succeeds" "$?" "0"
check "and adds nothing" "$(find "$h/.config/hypr/themes" -mindepth 1 | wc -l | tr -d ' ')" "0"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
