#!/bin/bash
# Turning live wallpaper off did not survive a login, and neither did picking a
# wallpaper by hand.
#
# autostart.lua ran this on every Hyprland start:
#
#   live-wallpaper-toggle.sh on
#
# and "on" turns it on unless the flag file already says it is on. Turning it
# off with SUPER+CTRL+W removes that flag, so the next login turned it straight
# back on and restored the 30 second cycling. Picking a wallpaper with SUPER+W
# clears the same flag, on purpose, to pin the choice, so a manual pick was
# undone by the next login too.
#
# A toggle whose state is reset at every login is not a toggle. Measured before
# the fix: off, then a login, and hyprpaper.conf had its timeout back.
#
# autostart now runs "apply", which puts hyprpaper in whatever state the flag
# already records without changing it.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"; mkdir -p "$STUB"
for t in systemctl notify-send hyprctl; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$t"; chmod +x "$STUB/$t"
done

HOME_DIR="$TMP/home"
setup() {
  rm -rf "${TMP:?}/home"
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.cache" \
    "$HOME_DIR/.config/hypr/themes/demo/backgrounds"
  cp "$BIN/live-wallpaper-toggle.sh" "$BIN/hypr-helpers.sh" "$HOME_DIR/.local/bin/"
  printf 'x\n' >"$HOME_DIR/.config/hypr/themes/demo/backgrounds/a.jpg"
  printf 'x\n' >"$HOME_DIR/.config/hypr/themes/demo/backgrounds/b.jpg"
  printf '%s\n' "$HOME_DIR/.config/hypr/themes/demo/backgrounds/a.jpg" \
    >"$HOME_DIR/.cache/current_wallpaper_path"
  printf 'x\n' >"$HOME_DIR/.cache/current_wallpaper"
  touch "$HOME_DIR/.cache/live_wallpaper_enabled"
}
run() {
  HOME="$HOME_DIR" PATH="$STUB:/usr/bin:/bin" \
    bash "$HOME_DIR/.local/bin/live-wallpaper-toggle.sh" "$1" >/dev/null 2>&1
}
flag() { [[ -f $HOME_DIR/.cache/live_wallpaper_enabled ]] && echo on || echo off; }
# grep -c prints 0 and exits 1 when it matches nothing, so a `|| echo 0` here
# appends a second line rather than supplying a missing one.
cycling() {
  local n
  n=$(grep -c 'timeout' "$HOME_DIR/.config/hypr/hyprpaper.conf" 2>/dev/null) || n=0
  printf '%s' "$n"
}

# What autostart does at login. Named for what it is, so the checks read as the
# sequence a person actually goes through.
login() { run apply; }

# --- turning it off lasts ----------------------------------------------------

setup
run off
check "turning it off clears the flag" "$(flag)" "off"
check "and stops the cycling" "$(cycling)" "0"
login
check "and a login leaves it off" "$(flag)" "off"
check "with the cycling still stopped" "$(cycling)" "0"

# --- leaving it on lasts too, which is the default -------------------------
#
# Without this the fix could be a way to never turn live wallpaper on at all.

setup
login
check "a fresh install stays on through a login" "$(flag)" "on"
check "and keeps cycling" "$(cycling)" "1"

setup
run on
login
check "turning it on and logging in leaves it on" "$(flag)" "on"
check "and cycling" "$(cycling)" "1"

# --- a hand-picked wallpaper survives ---------------------------------------
#
# wallpaper-switcher.sh clears the same flag to pin a choice, so this is the
# same failure wearing different clothes.

setup
rm -f "$HOME_DIR/.cache/live_wallpaper_enabled"   # what SUPER+W leaves behind
login
check "a hand-picked wallpaper is not overridden at login" "$(flag)" "off"
check "and hyprpaper still points at the single file" \
  "$(grep -c 'current_wallpaper' "$HOME_DIR/.config/hypr/hyprpaper.conf")" "1"

# --- apply changes nothing but the conf --------------------------------------

setup
before=$(md5sum "$HOME_DIR/.cache/current_wallpaper_path" | cut -d' ' -f1)
login
check "apply does not rewrite the recorded wallpaper path" \
  "$(md5sum "$HOME_DIR/.cache/current_wallpaper_path" | cut -d' ' -f1)" "$before"

# --- the toggle itself still works ------------------------------------------

setup
run ""
check "a bare invocation still toggles off from on" "$(flag)" "off"
run ""
check "and back on" "$(flag)" "on"

# --- autostart calls apply, not on ------------------------------------------

# Only whole-line comments. In lua, "--" is also two ordinary characters, and
# `uwsm app -- waybar` is a real command in this very file: cutting at the
# first "--" anywhere deleted half the code it was meant to preserve.
code_of() { sed 's/^[[:space:]]*--.*//' "$1"; }
check "autostart runs apply" \
  "$(code_of "$REPO/default/hypr/autostart.lua" | grep -c 'live-wallpaper-toggle.sh apply')" "1"
check "and no longer forces it on" \
  "$(code_of "$REPO/default/hypr/autostart.lua" | grep -c 'live-wallpaper-toggle.sh on')" "0"
# Naming a command that must survive, rather than a line count: a count is
# either brittle or, if read from the file itself, a comparison with itself.
check "stripping comments leaves the file's code intact" \
  "$(code_of "$REPO/default/hypr/autostart.lua" | grep -c 'uwsm app -- waybar')" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
