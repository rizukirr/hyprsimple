#!/bin/bash
# btop was themed everywhere except in btop.
#
# hyprsimple installs btop, install.sh creates ~/.config/btop/themes, all
# sixteen shipped themes render a btop.theme, and every theme switch copied one
# to themes/current.theme. Nothing ever told btop to read it. btop selects a
# theme by the color_theme key in its own config, and that said:
#
#   color_theme = "Default"
#
# which is what btop writes for itself on first run. Measured on a live install
# with rosepine active: themes/current.theme held rosepine's colours, and
# btop.conf still said "Default". The themed btop has never worked anywhere.
#
# This is the shape the wlogout colours had, inverted: there a stylesheet was
# wired to colours nothing rendered, here colours are rendered and delivered
# and nothing selects them.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
MIGRATION="$REPO/migrations/1788636400.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the premise ------------------------------------------------------------

# The switcher reads the generated theme, not one shipped per theme, so what
# matters is that every theme renders one: a colors.toml plus the template.
# Checking for a shipped btop.theme instead would have been asking the wrong
# question, and one theme does not have one.
themes=0; with_colors=0
for t in "$REPO/.config/hypr/themes"/*/; do
  name=$(basename "$t"); [[ $name == templates* ]] && continue
  themes=$((themes + 1))
  [[ -f $t/colors.toml ]] && with_colors=$((with_colors + 1))
done
if (( themes < 5 )); then
  fail "found $themes themes, too few for this to mean anything"
else
  pass "checked $themes shipped themes"
fi
check "the btop template exists, so a theme can be rendered at all" \
  "$([[ -f $REPO/.config/hypr/themes/templates/btop.theme.tpl ]] && echo yes || echo no)" "yes"
check "every theme has the colors the template needs, so every switch renders one" \
  "$with_colors" "$themes"
check "and btop is a package hyprsimple installs" \
  "$(grep -cx 'btop' "$REPO/packages.txt")" "1"
check "and hyprsimple ships no btop config of its own, which is why nothing set the key" \
  "$([[ -d $REPO/.config/btop ]] && echo yes || echo no)" "no"

# --- the switcher selects it ------------------------------------------------

STUB="$TMP/bin"; mkdir -p "$STUB"
for tool in gsettings hyprctl systemctl pkill busctl hyprsimple-restart-waybar.sh; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$tool"; chmod +x "$STUB/$tool"
done

HOME_DIR="$TMP/home"
setup_home() {
  rm -rf "${TMP:?}/home"
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/uwsm" "$HOME_DIR/.cache" \
    "$HOME_DIR/.config/hypr/themes/demo/generated"
  cp "$BIN/theme-switcher.sh" "$BIN/hypr-helpers.sh" "$BIN/theme-apply-templates.sh" \
    "$HOME_DIR/.local/bin/"
  printf 'theme[main_bg]="#191724"\n' \
    >"$HOME_DIR/.config/hypr/themes/demo/generated/btop.theme"
}
switch() {
  HOME="$HOME_DIR" THEME_SWITCHER_NO_RELOAD=1 PATH="$STUB:/usr/bin:/bin" \
    bash "$HOME_DIR/.local/bin/theme-switcher.sh" demo >/dev/null 2>&1
}
btop_conf() { cat "$HOME_DIR/.config/btop/btop.conf" 2>/dev/null; }

setup_home
switch
check "the generated theme is still copied into place" \
  "$([[ -f $HOME_DIR/.config/btop/themes/current.theme ]] && echo yes || echo no)" "yes"
check "and with no btop.conf one is written that selects it" \
  "$(btop_conf | grep -c '^color_theme = "current"$')" "1"

# btop writes a full config on first run, with its own default selected.
setup_home
mkdir -p "$HOME_DIR/.config/btop"
printf 'truecolor = true\ncolor_theme = "Default"\nvim_keys = false\n' \
  >"$HOME_DIR/.config/btop/btop.conf"
switch
check "an existing config has the key replaced" \
  "$(btop_conf | grep -c '^color_theme = "current"$')" "1"
check "and not appended, which would leave two" \
  "$(btop_conf | grep -c '^color_theme = ')" "1"
check "and every other setting is kept" \
  "$(btop_conf | grep -c 'truecolor\|vim_keys')" "2"

setup_home
mkdir -p "$HOME_DIR/.config/btop"
printf 'truecolor = true\n' >"$HOME_DIR/.config/btop/btop.conf"
switch
check "a config with no color_theme line gains one" \
  "$(btop_conf | grep -c '^color_theme = "current"$')" "1"
check "and keeps what was there" "$(btop_conf | grep -c 'truecolor')" "1"

# A theme with no btop.theme must not touch btop at all.
setup_home
rm "$HOME_DIR/.config/hypr/themes/demo/generated/btop.theme"
switch
check "a theme with no btop theme writes no btop config" \
  "$([[ -f $HOME_DIR/.config/btop/btop.conf ]] && echo yes || echo no)" "no"

# --- the migration ----------------------------------------------------------

mk() {
  rm -rf "${TMP:?}/mhome"; mkdir -p "$TMP/mhome/.config/btop/themes"
  printf 'theme[main_bg]="#191724"\n' >"$TMP/mhome/.config/btop/themes/current.theme"
  [[ -n ${1:-} ]] && printf '%s\n' "$1" >"$TMP/mhome/.config/btop/btop.conf"
  return 0
}
run_migration() { HOME="$TMP/mhome" bash "$MIGRATION" >"$TMP/out" 2>&1; }
mconf() { cat "$TMP/mhome/.config/btop/btop.conf" 2>/dev/null; }

mk 'color_theme = "Default"'
run_migration
check "a config left on btop's default is switched over" \
  "$(mconf | grep -c '^color_theme = "current"$')" "1"
check "and the previous one is kept" \
  "$([[ -f $TMP/mhome/.config/btop/btop.conf.bak ]] && echo yes || echo no)" "yes"

mk 'color_theme = "gruvbox_dark"'
run_migration
check "a theme the user chose is left alone" \
  "$(mconf)" 'color_theme = "gruvbox_dark"'
check "and they are told how to switch" "$(grep -c 'color_theme = ' "$TMP/out")" "1"
check "and no backup is written, nothing having changed" \
  "$([[ -f $TMP/mhome/.config/btop/btop.conf.bak ]] && echo yes || echo no)" "no"

mk 'color_theme = "current"'
run_migration
check "an already correct config is untouched" \
  "$([[ -f $TMP/mhome/.config/btop/btop.conf.bak ]] && echo yes || echo no)" "no"

mk ''
run_migration
check "no btop.conf at all gets one" \
  "$(mconf | grep -c '^color_theme = "current"$')" "1"

rm -rf "${TMP:?}/mhome"; mkdir -p "$TMP/mhome/.config/btop"
run_migration
check "a home with no generated theme is left alone and says so" \
  "$(grep -c 'Switching theme will write one' "$TMP/out")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
