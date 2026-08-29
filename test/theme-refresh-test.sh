#!/bin/bash
# Checks the theme refresh migration against fixtures.
# Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788019274.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# An install that ships one theme, and a user config holding the older shape of
# it: a .png the install now ships as .jpg, a dead rofi tree, a lockscreen.png,
# a generated/ directory, and one wallpaper the user added themselves.
inst="$TMP/install/.config/hypr/themes/demo"
home="$TMP/home/.config/hypr/themes/demo"
mkdir -p "$inst/backgrounds" "$home/backgrounds" "$home/rofi/launcher" "$home/generated"

printf 'new-small\n' >"$inst/backgrounds/0-sky.jpg"
printf 'colors\n'    >"$inst/colors.toml"

printf 'old-huge-version\n' >"$home/backgrounds/0-sky.png"
printf 'mine\n'             >"$home/backgrounds/my-own-photo.jpg"
printf 'dead\n'             >"$home/rofi/launcher/style.rasi"
printf 'dead\n'             >"$home/lockscreen.png"
printf 'built\n'            >"$home/generated/hyprland-colors.lua"
printf 'stale\n'            >"$home/colors.toml"

HOME="$TMP/home" HYPRSIMPLE_PATH="$TMP/install" bash "$MIGRATION" >"$TMP/out" 2>&1
check "migration exits 0" "$?" "0"

check "the shipped file is copied in"        "$(cat "$home/backgrounds/0-sky.jpg" 2>/dev/null)" "new-small"
check "a differing shipped file is updated"  "$(cat "$home/colors.toml" 2>/dev/null)"           "colors"
check "the superseded .png is removed"       "$([[ -e $home/backgrounds/0-sky.png ]] && echo present || echo gone)" gone
check "the dead rofi tree is removed"        "$([[ -e $home/rofi ]] && echo present || echo gone)" gone
check "lockscreen.png is removed"            "$([[ -e $home/lockscreen.png ]] && echo present || echo gone)" gone
check "generated/ survives"                  "$(cat "$home/generated/hyprland-colors.lua" 2>/dev/null)" "built"
check "a file the user added survives"       "$(cat "$home/backgrounds/my-own-photo.jpg" 2>/dev/null)" "mine"

if grep -q "Left 1 file" "$TMP/out"; then pass "the kept file is reported"
else printf 'not ok - the kept file is reported\n' >&2; failures=$((failures + 1)); fi

# A second run must change nothing.
snap=$(find "$TMP/home" -type f -exec md5sum {} + | sort)
HOME="$TMP/home" HYPRSIMPLE_PATH="$TMP/install" bash "$MIGRATION" >/dev/null 2>&1
check "migration is idempotent" "$(find "$TMP/home" -type f -exec md5sum {} + | sort)" "$snap"

# A theme the install does not ship is left entirely alone.
mkdir -p "$TMP/home/.config/hypr/themes/mytheme/backgrounds"
printf 'custom\n' >"$TMP/home/.config/hypr/themes/mytheme/backgrounds/x.jpg"
HOME="$TMP/home" HYPRSIMPLE_PATH="$TMP/install" bash "$MIGRATION" >/dev/null 2>&1
check "a user's own theme is untouched" \
  "$(cat "$TMP/home/.config/hypr/themes/mytheme/backgrounds/x.jpg" 2>/dev/null)" "custom"

# A missing config directory is a no-op.
HOME="$TMP/nothing" HYPRSIMPLE_PATH="$TMP/install" bash "$MIGRATION" >/dev/null 2>&1
check "a missing config dir exits 0" "$?" "0"

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
