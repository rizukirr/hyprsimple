#!/bin/bash
# Checks that wlogout follows the active theme: the template renders, the theme
# switcher installs the colours, the stylesheet parses, and the migration never
# leaves style.css importing a file that is not there.
# Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="$REPO/.local/bin/theme-apply-templates.sh"
MIGRATION="$REPO/migrations/1788279207.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'not ok - refusing to operate outside the fixture: %s\n' "${1:-<empty>}" >&2
    exit 1
  fi
}

STYLE="$REPO/.config/wlogout/style.css"
check "style.css imports the colour file" \
  "$(grep -c '@import url("wlogout-colors.css")' "$STYLE")" "1"
check "style.css has no hardcoded catppuccin colours left" \
  "$(grep -cE '#(11111b|cdd6f4)' "$STYLE")" "0"
check "a fallback colour file is shipped" \
  "$([[ -f $REPO/.config/wlogout/wlogout-colors.css ]] && echo yes || echo no)" "yes"
check "every colour the stylesheet names is defined by the fallback" \
  "$(grep -oE '@wl_[a-z]+' "$STYLE" | sort -u | while read -r c; do
       grep -q "define-color ${c#@} " "$REPO/.config/wlogout/wlogout-colors.css" || echo miss
     done | grep -c miss)" "0"

THEME="$TMP/theme"
must_be_fixture "$THEME"
INST="$TMP/install"
HOMEDIR="$TMP/home"
mkdir -p "$INST/.config/hypr/themes" "$HOMEDIR/.config"
cp -r "$REPO/.config/hypr/themes/templates" "$INST/.config/hypr/themes/templates"
mkdir -p "$THEME"
printf 'background = "#2d353b"\nforeground = "#d3c6aa"\n' >"$THEME/colors.toml"
HOME="$HOMEDIR" HYPRSIMPLE_PATH="$INST" bash "$RENDER" "$THEME" >/dev/null 2>&1
check "the theme's background reaches the rendered colours" \
  "$(grep -c 'wl_background #2d353b' "$THEME/generated/wlogout-colors.css")" "1"
check "the theme's foreground reaches the rendered colours" \
  "$(grep -c 'wl_foreground #d3c6aa' "$THEME/generated/wlogout-colors.css")" "1"

# The failure this guards against is specific: GTK treats a missing @import as
# fatal and returns an empty stylesheet, so wlogout renders with no styling at
# all. Asserting the file merely exists would not catch a stylesheet that
# parses to nothing.

PARSE="$TMP/parse"
mkdir -p "$PARSE"
cp "$STYLE" "$PARSE/style.css"
cp "$THEME/generated/wlogout-colors.css" "$PARSE/wlogout-colors.css"
if python3 -c "import gi; gi.require_version('Gtk','3.0')" 2>/dev/null; then
  parsed=$(python3 - "$PARSE/style.css" <<'PY'
import sys, gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gio
p = Gtk.CssProvider()
try:
    p.load_from_file(Gio.File.new_for_path(sys.argv[1]))
except Exception:
    print("error"); raise SystemExit
print("empty" if not p.to_string().strip() else "styled")
PY
)
  check "GTK parses the stylesheet with its colours to a non-empty result" "$parsed" "styled"

  rm -f "$PARSE/wlogout-colors.css"
  broken=$(python3 - "$PARSE/style.css" <<'PY'
import sys, gi
gi.require_version('Gtk', '3.0')
from gi.repository import Gtk, Gio
p = Gtk.CssProvider()
try:
    p.load_from_file(Gio.File.new_for_path(sys.argv[1]))
except Exception:
    print("error"); raise SystemExit
print("empty" if not p.to_string().strip() else "styled")
PY
)
  check "and without the colour file it is fatal, which is why order matters" "$broken" "error"
else
  # Not installed in CI on purpose: the GTK3 stack costs minutes per run to
  # install, and what these two checks pin is GTK's own behaviour, which does
  # not change per pull request. The checks that constrain this repository's
  # code, that the import is present and that every colour it names is defined,
  # run everywhere. These run on a developer machine.
  printf 'skip - python gtk3 bindings absent, stylesheet not parsed here\n'
fi

# The pre-theming style.css, pinned as a fixture rather than read from git
# history. CI checks out shallow, so `git log ... | tail -1` there resolves to
# HEAD and hands back the themed file, and the migration checks below would
# compare it against itself and pass without testing anything.
PRESPLIT_STYLE="$REPO/test/fixtures/wlogout/style.presplit.css"

new_home() {
  HOMEDIR="$TMP/$1"
  must_be_fixture "$HOMEDIR"
  mkdir -p "$HOMEDIR/.config/wlogout"
  cp "$PRESPLIT_STYLE" "$HOMEDIR/.config/wlogout/style.css"
  if ! grep -q '#11111b' "$HOMEDIR/.config/wlogout/style.css"; then
    printf 'not ok - fixture is not the pre-theming stylesheet (%s)\n' "$1" >&2
    exit 1
  fi
}

new_home pristine
HOME="$HOMEDIR" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/mig_out" 2>&1
check "a pristine style.css is replaced with the themed one" \
  "$(cmp -s "$HOMEDIR/.config/wlogout/style.css" "$STYLE" && echo same || echo different)" "same"
check "and the file it imports exists afterwards" \
  "$([[ -f $HOMEDIR/.config/wlogout/wlogout-colors.css ]] && echo yes || echo no)" "yes"

new_home edited
printf '\n/* mine */\n' >>"$HOMEDIR/.config/wlogout/style.css"
before=$(md5sum "$HOMEDIR/.config/wlogout/style.css" | cut -d' ' -f1)
HOME="$HOMEDIR" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/mig_edit" 2>&1
check "an edited style.css is left byte-identical" \
  "$(md5sum "$HOMEDIR/.config/wlogout/style.css" | cut -d' ' -f1)" "$before"
check "and the user is told how to take it" \
  "$(grep -c 'refresh-config.sh wlogout/style.css' "$TMP/mig_edit")" "1"

HOME="$HOMEDIR" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >/dev/null 2>&1
check "a second run exits 0" "$?" "0"

# The theming migration installs the fallback and updates style.css but does
# not render, so without this an existing install sits on the fallback's
# catppuccin colours until its next theme switch. A build input that is never
# built reaches nobody.

RENDER_MIGRATION="$REPO/migrations/1788280106.sh"

HOMEDIR="$TMP/render"
must_be_fixture "$HOMEDIR"
mkdir -p "$HOMEDIR/.local/bin" "$HOMEDIR/.config/hypr/themes/solo" "$HOMEDIR/.config/wlogout"
cp "$RENDER" "$HOMEDIR/.local/bin/theme-apply-templates.sh"
chmod +x "$HOMEDIR/.local/bin/theme-apply-templates.sh"
printf 'background = "#2d353b"\nforeground = "#d3c6aa"\n' >"$HOMEDIR/.config/hypr/themes/solo/colors.toml"
mkdir -p "$HOMEDIR/.config/hypr/themes/solo/generated"
ln -sfn "$HOMEDIR/.config/hypr/themes/solo/generated/hyprland-colors.lua" \
  "$HOMEDIR/.config/hypr/theme-active.lua"
cp "$REPO/.config/wlogout/wlogout-colors.css" "$HOMEDIR/.config/wlogout/wlogout-colors.css"

check "before the render migration wlogout holds the fallback" \
  "$(grep -c 'wl_background #11111b' "$HOMEDIR/.config/wlogout/wlogout-colors.css")" "1"

HOME="$HOMEDIR" HYPRSIMPLE_PATH="$REPO" bash "$RENDER_MIGRATION" >"$TMP/render_out" 2>&1
check "the template is rendered for an existing theme" \
  "$(grep -c 'wl_background #2d353b' "$HOMEDIR/.config/hypr/themes/solo/generated/wlogout-colors.css")" "1"
check "and the active theme's colours reach wlogout" \
  "$(grep -c 'wl_background #2d353b' "$HOMEDIR/.config/wlogout/wlogout-colors.css")" "1"

before_render=$(md5sum "$HOMEDIR/.config/wlogout/wlogout-colors.css" | cut -d' ' -f1)
HOME="$HOMEDIR" HYPRSIMPLE_PATH="$REPO" bash "$RENDER_MIGRATION" >/dev/null 2>&1
check "a second render run changes nothing" \
  "$(md5sum "$HOMEDIR/.config/wlogout/wlogout-colors.css" | cut -d' ' -f1)" "$before_render"

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
