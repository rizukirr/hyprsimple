#!/bin/bash
# The cursor a theme declares never survived a login, and on a fresh install it
# was never applied at all.
#
# theme-switcher.sh set it two ways, both of which end at logout:
#
#   gsettings set org.gnome.desktop.interface cursor-theme "$CURSOR"
#   hyprctl setcursor "$CURSOR" 24
#
# gsettings reaches GTK and setcursor reaches the running Hyprland. XCURSOR_THEME
# is what a new session reads, and what XWayland, SDL and Qt read, and the
# switcher never wrote it. install.sh wrote it once, at the very end, and only
# when the theme it installed with shipped a cursor-theme file:
#
#   if [[ -f "$THEME_DIR/cursor-theme" ]]; then
#     echo "export XCURSOR_THEME=$CURSOR" >> "$HOME/.config/uwsm/env"
#
# The install-time default is deep-sea, which has no such file. Two of the
# sixteen shipped themes have one at all. So XCURSOR_THEME was unset on a fresh
# install, and switching to catppuccin or rosepine, which do declare a cursor,
# did not set it either. Confirmed on the maintainer's machine: active theme
# rosepine, which declares Adwaita-dark, and XCURSOR_THEME unset in the running
# session.
#
# uwsm carries XCURSOR_THEME in UWSM_FINALIZE_VARNAMES, so the variable is the
# mechanism this setup already expects.

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

# --- the premise: the default theme declares no cursor ----------------------

themes=0; with_cursor=0
for t in "$REPO/.config/hypr/themes"/*/; do
  name=$(basename "$t"); [[ $name == templates* ]] && continue
  themes=$((themes + 1))
  [[ -f $t/cursor-theme ]] && with_cursor=$((with_cursor + 1))
done
if (( themes < 5 )); then
  fail "found $themes themes, which is too few for this check to mean anything"
else
  pass "checked $themes shipped themes"
fi
check "the install-time default theme declares no cursor, so install.sh alone never set one" \
  "$([[ -f $REPO/.config/hypr/themes/deep-sea/cursor-theme ]] && echo yes || echo no)" "no"
if (( with_cursor > 0 )); then
  pass "$with_cursor themes do declare a cursor, so there is something to persist"
else
  fail "no theme declares a cursor, so this suite is testing nothing"
fi

check "install.sh no longer writes XCURSOR_THEME itself" \
  "$(grep -c 'XCURSOR_THEME' "$REPO/install.sh")" "0"

# --- the switcher persists it ------------------------------------------------

STUB="$TMP/bin"; mkdir -p "$STUB"
for tool in gsettings hyprctl systemctl pkill hyprsimple-restart-waybar.sh; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$tool"; chmod +x "$STUB/$tool"
done

HOME_DIR="$TMP/home"
setup_home() {
  rm -rf "${TMP:?}/home"
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/uwsm" "$HOME_DIR/.cache" \
    "$HOME_DIR/.config/hypr/themes/withcursor" "$HOME_DIR/.config/hypr/themes/plain"
  cp "$BIN/theme-switcher.sh" "$BIN/hypr-helpers.sh" "$BIN/theme-apply-templates.sh" \
    "$HOME_DIR/.local/bin/"
  printf 'Adwaita-dark\n' >"$HOME_DIR/.config/hypr/themes/withcursor/cursor-theme"
  cat >"$HOME_DIR/.config/uwsm/env" <<'ENVEOF'
export XCURSOR_SIZE=24
export GDK_BACKEND="wayland,x11,*"
ENVEOF
}
switch_to() {
  HOME="$HOME_DIR" THEME_SWITCHER_NO_RELOAD=1 PATH="$STUB:/usr/bin:/bin" \
    bash "$HOME_DIR/.local/bin/theme-switcher.sh" "$1" >/dev/null 2>&1
}
env_file() { cat "$HOME_DIR/.config/uwsm/env"; }

setup_home
check "the fixture starts with no XCURSOR_THEME" \
  "$(env_file | grep -c XCURSOR_THEME)" "0"

switch_to withcursor
check "switching to a theme that declares a cursor writes XCURSOR_THEME" \
  "$(env_file | grep -c '^export XCURSOR_THEME=Adwaita-dark$')" "1"
check "and the rest of the file is kept" \
  "$(env_file | grep -c 'XCURSOR_SIZE\|GDK_BACKEND')" "2"

# The file is read once at login, so a second export would win silently and the
# file would grow a line per switch.
printf 'Bibata-Original-Classic\n' >"$HOME_DIR/.config/hypr/themes/withcursor/cursor-theme"
switch_to withcursor
check "switching again replaces the line rather than appending one" \
  "$(env_file | grep -c '^export XCURSOR_THEME=')" "1"
check "and it holds the new value" \
  "$(env_file | grep -c '^export XCURSOR_THEME=Bibata-Original-Classic$')" "1"

# A theme with no cursor-theme file leaves the setting alone, which is what
# gsettings and setcursor already did. Changing that is a separate decision.
switch_to plain
check "a theme that declares no cursor leaves the value alone" \
  "$(env_file | grep -c '^export XCURSOR_THEME=Bibata-Original-Classic$')" "1"

# The two runtime paths still happen, so this is not a swap of one mechanism
# for another.
check "gsettings is still called" \
  "$(grep -c 'gsettings set org.gnome.desktop.interface cursor-theme' "$BIN/theme-switcher.sh")" "1"
# Anchored to the code, not the prose: the comment added beside it names
# `hyprctl setcursor` too, and a bare grep counted both.
check "and hyprctl setcursor is still called" \
  "$(grep -c '^ *\[\[ -z "\$THEME_SWITCHER_NO_RELOAD" \]\] && hyprctl setcursor' "$BIN/theme-switcher.sh")" "1"

# No uwsm/env at all must not break a theme switch.
setup_home
rm -f "$HOME_DIR/.config/uwsm/env"
switch_to withcursor
check "a home with no uwsm/env still switches theme without error" \
  "$([[ -e $HOME_DIR/.config/uwsm/env ]] && echo created || echo absent)" "absent"
check "and leaves no temporary file behind" \
  "$(find "$HOME_DIR/.config/uwsm" -name 'env.tmp.*' | wc -l | tr -d ' ')" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
