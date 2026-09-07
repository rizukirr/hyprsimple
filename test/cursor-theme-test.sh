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
# rosepine, and XCURSOR_THEME unset in the running session.
#
# Both of those declared values were themselves wrong, found later: catppuccin
# named catppuccin-mocha-lavender-cursors and rosepine named Adwaita-dark,
# neither of which is an installed cursor theme. They name Adwaita now, and
# theme-switcher.sh refuses one with no cursors/ directory rather than passing
# it to hyprctl, which answers "ok" either way.
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

# Comments stripped before counting. install.sh explains in a comment that
# theme-switcher.sh replaces rather than appends for XCURSOR_THEME, and an
# unanchored grep counted that explanation as code.
check "install.sh no longer writes XCURSOR_THEME itself" \
  "$(sed 's/#.*//' "$REPO/install.sh" | grep -c 'XCURSOR_THEME')" "0"
check "and stripping comments leaves its code behind" \
  "$(sed 's/#.*//' "$REPO/install.sh" | grep -c '^set_env_block()')" "1"

# --- the switcher persists it ------------------------------------------------

STUB="$TMP/bin"; mkdir -p "$STUB"
# A rofi that answers with nothing, never the real one. These scripts open a
# picker when given no argument and /usr/bin is on the PATH below, so the real
# rofi was reachable from here. It reached the maintainer's screen once, from a
# suite that had no stub, and opened a window complaining about a theme inside
# the fixture.
printf '#!/bin/bash\nexit 1\n' >"$STUB/rofi"
# notify-send among them. theme-switcher.sh warns when a theme names a cursor
# that is not installed, and this suite drives exactly that case, so without a
# stub the warning went to the maintainer's own desktop. It did, once.
for tool in gsettings hyprctl systemctl pkill hyprsimple-restart-waybar.sh notify-send; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$tool"; chmod +x "$STUB/$tool"
done

HOME_DIR="$TMP/home"
setup_home() {
  rm -rf "${TMP:?}/home"
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/uwsm" "$HOME_DIR/.cache" \
    "$HOME_DIR/.config/hypr/themes/withcursor" "$HOME_DIR/.config/hypr/themes/plain"
  # theme-switcher.sh requires both helpers before it will run, so the
  # fixture carries both even though this file only reads the cursor half.
  cp "$BIN/theme-switcher.sh" "$BIN/hypr-helpers.sh" "$BIN/theme-apply-templates.sh" \
    "$BIN/hyprsimple-require.sh" "$BIN/hyprsimple-theme-deliver.sh" \
    "$HOME_DIR/.local/bin/"
  printf 'FixtureCursor\n' >"$HOME_DIR/.config/hypr/themes/withcursor/cursor-theme"
  # A real cursor theme inside the fixture home. theme-switcher.sh refuses a
  # cursor theme with no cursors/ directory now, because two shipped themes
  # named ones nothing installs and nothing reported it: hyprctl setcursor
  # answers "ok" either way. A fixture naming a theme that does not exist would
  # exercise that refusal instead of the export these checks are about.
  mkdir -p "$HOME_DIR/.local/share/icons/FixtureCursor/cursors"
  mkdir -p "$HOME_DIR/.local/share/icons/OtherCursor/cursors"
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
  "$(env_file | grep -c '^export XCURSOR_THEME=FixtureCursor$')" "1"
check "and the rest of the file is kept" \
  "$(env_file | grep -c 'XCURSOR_SIZE\|GDK_BACKEND')" "2"

# The file is read once at login, so a second export would win silently and the
# file would grow a line per switch.
printf 'OtherCursor\n' >"$HOME_DIR/.config/hypr/themes/withcursor/cursor-theme"
switch_to withcursor
check "switching again replaces the line rather than appending one" \
  "$(env_file | grep -c '^export XCURSOR_THEME=')" "1"
check "and it holds the new value" \
  "$(env_file | grep -c '^export XCURSOR_THEME=OtherCursor$')" "1"

# A theme with no cursor-theme file leaves the setting alone, which is what
# gsettings and setcursor already did. Changing that is a separate decision.
switch_to plain
check "a theme that declares no cursor leaves the value alone" \
  "$(env_file | grep -c '^export XCURSOR_THEME=OtherCursor$')" "1"

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

# ---- a cursor theme that is not installed is refused --------------------------
#
# hyprctl setcursor answers "ok" for a theme that does not exist and gsettings
# stores whatever it is given, so nothing ever reported that two shipped themes
# named cursors nothing installs: catppuccin asked for
# catppuccin-mocha-lavender-cursors, in no package list and no repository, and
# rosepine asked for Adwaita-dark, which is a GTK theme name. Measured on a live
# machine, the only directories with a cursors/ subdirectory were Adwaita and
# Yaru.
#
# It outlives the switch: XCURSOR_THEME goes into uwsm/env and is read at every
# login, so a name resolving to nothing persists past the theme that set it.
#
# Its own setup_home, because the section above deletes uwsm/env and these need
# a previous value to show is left standing.
setup_home
switch_to withcursor
check "the fixture starts with a cursor theme that does exist" \
  "$(env_file | grep -c '^export XCURSOR_THEME=FixtureCursor$')" "1"

printf 'NoSuchCursorTheme\n' >"$HOME_DIR/.config/hypr/themes/withcursor/cursor-theme"
switch_to withcursor
check "a cursor theme with no cursors directory is not exported" \
  "$(env_file | grep -c '^export XCURSOR_THEME=NoSuchCursorTheme$')" "0"
check "and the previous value is left standing rather than cleared" \
  "$(env_file | grep -c '^export XCURSOR_THEME=FixtureCursor$')" "1"

# A directory without cursors/ inside it is a name, not a cursor theme. That is
# exactly the shape of rosepine's Adwaita-dark, which exists as a GTK theme name
# and never as a cursor theme.
mkdir -p "$HOME_DIR/.local/share/icons/NotACursorTheme"
printf 'NotACursorTheme\n' >"$HOME_DIR/.config/hypr/themes/withcursor/cursor-theme"
switch_to withcursor
check "an icon directory with no cursors subdirectory is refused too" \
  "$(env_file | grep -c '^export XCURSOR_THEME=NotACursorTheme$')" "0"

# And the refusal is not blanket: adding the subdirectory makes it acceptable.
mkdir -p "$HOME_DIR/.local/share/icons/NotACursorTheme/cursors"
switch_to withcursor
check "and accepted once it has one, so the check is about cursors/ and not the name" \
  "$(env_file | grep -c '^export XCURSOR_THEME=NotACursorTheme$')" "1"

# ---- every shipped theme names a cursor theme that could exist ---------------
#
# Read out of the repository rather than listed here. On a machine with the
# icon packages installed this checks they are really there; on one without, it
# checks the value at least looks like a cursor theme rather than a GTK theme.

shipped_cursors=()
while IFS= read -r file; do
  shipped_cursors+=("$(basename "$(dirname "$file")"):$(cat "$file")")
done < <(find "$REPO/.config/hypr/themes" -maxdepth 2 -name cursor-theme | sort)

if (( ${#shipped_cursors[@]} == 0 )); then
  fail "no theme ships a cursor-theme file, so this check reads nothing"
else
  pass "found ${#shipped_cursors[@]} theme(s) declaring a cursor"
fi

missing=()
for entry in "${shipped_cursors[@]}"; do
  name="${entry#*:}"
  found=no
  for dir in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
    [[ -d $dir/$name/cursors ]] && found=yes
  done
  [[ $found == no ]] && missing+=("$entry")
done

if (( ${#missing[@]} > 0 )) && [[ ! -d /usr/share/icons/Adwaita/cursors ]]; then
  # No cursor themes installed at all, which is a CI runner. Saying so rather
  # than reporting every theme as broken.
  pass "no cursor themes are installed here, so the shipped names are not checked"
else
  missing_str=""
  (( ${#missing[@]} > 0 )) && missing_str="$(printf '%s ' "${missing[@]}")"
  check "every shipped theme names a cursor theme that is installed" "$missing_str" ""
fi

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
