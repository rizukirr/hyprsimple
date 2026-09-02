#!/bin/bash
# Checks that theme templates are delivered from the install rather than from
# whatever a home directory happens to hold, while a genuinely customised home
# template still wins. Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDER="$REPO/.local/bin/theme-apply-templates.sh"
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

# One install, one template, one colour. Every case below renders a theme and
# reads the rendered file, never the renderer's own text: a grep for a path
# would prove the line exists, not that resolution works.
new_case() {
  local name="$1"
  CASE="$TMP/$name"
  must_be_fixture "$CASE"
  INST="$CASE/install"
  HOMEDIR="$CASE/home"
  THEME="$CASE/theme"
  mkdir -p "$INST/.config/hypr/themes/templates" "$HOMEDIR/.config/hypr" "$THEME"
  printf 'background = "#111111"\n' >"$THEME/colors.toml"
}

render() {
  HOME="$HOMEDIR" HYPRSIMPLE_PATH="$INST" bash "$RENDER" "$THEME" >"$CASE/out" 2>&1
  printf '%s' "$?" >"$CASE/rc"
}

rendered() { cat "$THEME/generated/$1" 2>/dev/null; }

# --- 1. a template only the install has -----------------------------------

new_case only-install
printf 'FROM-INSTALL {{ background }}\n' >"$INST/.config/hypr/themes/templates/probe.tpl"
render
check "a template only the install has is rendered" "$(rendered probe)" "FROM-INSTALL #111111"
check "the renderer exits 0" "$(cat "$CASE/rc")" "0"

# --- 2. a changed install template reaches a home that has no copy ---------

new_case changed-install
printf 'V1\n' >"$INST/.config/hypr/themes/templates/probe.tpl"
render
first=$(rendered probe)
printf 'V2\n' >"$INST/.config/hypr/themes/templates/probe.tpl"
render
check "a template changed in the install is delivered, no migration" \
  "$first -> $(rendered probe)" "V1 -> V2"

# --- 3. a home copy identical to the shipped one must not pin the install --
#
# install.sh copied every template into every existing home, so treating any
# home copy as an override would leave every existing install frozen. This is
# the check the whole change exists for.

new_case identical-copy
mkdir -p "$HOMEDIR/.config/hypr/themes/templates"
printf 'V1\n' >"$HOMEDIR/.config/hypr/themes/templates/probe.tpl"
printf 'V2\n' >"$INST/.config/hypr/themes/templates/probe.tpl"
render
check "a stale home copy does not shadow the install" "$(rendered probe)" "V2"
check "and the user is told it is being ignored" \
  "$(grep -c 'no longer used' "$CASE/out")" "1"

new_case identical-leftover
mkdir -p "$HOMEDIR/.config/hypr/themes/templates"
printf 'V1\n' >"$HOMEDIR/.config/hypr/themes/templates/probe.tpl"
printf 'V1\n' >"$INST/.config/hypr/themes/templates/probe.tpl"
render
check "an identical leftover is not warned about" \
  "$(grep -c 'no longer used' "$CASE/out")" "0"

# --- 4. a genuinely customised home template still wins --------------------

new_case customised
mkdir -p "$HOMEDIR/.config/hypr/themes/templates.user"
printf 'SHIPPED\n' >"$INST/.config/hypr/themes/templates/probe.tpl"
printf 'MINE {{ background }}\n' >"$HOMEDIR/.config/hypr/themes/templates.user/probe.tpl"
render
check "a templates.user override wins over the install" "$(rendered probe)" "MINE #111111"

new_case user-only
mkdir -p "$HOMEDIR/.config/hypr/themes/templates.user"
printf 'ONLY-MINE\n' >"$HOMEDIR/.config/hypr/themes/templates.user/extra.tpl"
printf 'S\n' >"$INST/.config/hypr/themes/templates/probe.tpl"
render
check "a templates.user file with no shipped counterpart renders" "$(rendered extra)" "ONLY-MINE"

# --- 5. a home with no template directory at all ---------------------------

new_case no-home-dir
printf 'A\n' >"$INST/.config/hypr/themes/templates/a.tpl"
printf 'B\n' >"$INST/.config/hypr/themes/templates/b.tpl"
render
check "every install template renders with no home directory" \
  "$(rendered a)$(rendered b)" "AB"

# --- 6. a template added to the install, home dir exists but lacks it ------

new_case added-template
mkdir -p "$HOMEDIR/.config/hypr/themes/templates"
printf 'OLD\n' >"$INST/.config/hypr/themes/templates/old.tpl"
printf 'NEW\n' >"$INST/.config/hypr/themes/templates/new.tpl"
render
check "a newly shipped template renders without a home copy" "$(rendered new)" "NEW"

# --- 7. every real shipped template still renders --------------------------

new_case real-templates
cp "$REPO/.config/hypr/themes/templates/"*.tpl "$INST/.config/hypr/themes/templates/"
cp "$REPO/.config/hypr/themes/everforest/colors.toml" "$THEME/colors.toml" 2>/dev/null ||
  printf 'background = "#111111"\n' >"$THEME/colors.toml"
render
# Arrays rather than counting ls output. The difference is a filename holding a
# newline, which ls reports as two lines and an array holds as one entry.
# Measured, not assumed: a space does not do this, and an earlier version of
# this comment claimed it did. It also drops a subprocess per count.
shipped=("$REPO/.config/hypr/themes/templates/"*.tpl)
rendered=("$THEME/generated"/*)
[[ -e ${rendered[0]} ]] || rendered=()
check "every shipped template produces a rendered file" \
  "${#rendered[@]}" "${#shipped[@]}"

# --- 8. no colors.toml is still a clean exit -------------------------------

new_case no-colors
rm -f "$THEME/colors.toml"
printf 'X\n' >"$INST/.config/hypr/themes/templates/probe.tpl"
render
check "a theme without colors.toml exits 0" "$(cat "$CASE/rc")" "0"

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
