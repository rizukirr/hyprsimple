#!/bin/bash
# Checks that an update re-renders themes when a template changed, so shipping
# a template is enough to deliver it and no migration has to re-render.
# Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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

STUB="$TMP/stub"
mkdir -p "$STUB"
for c in pgrep hyprctl pacman yay sudo systemctl git; do
  printf '#!/bin/sh\nexit 1\n' >"$STUB/$c"
  chmod +x "$STUB/$c"
done

INSTALL="$TMP/install"
HOMEDIR="$TMP/home"
must_be_fixture "$INSTALL"
must_be_fixture "$HOMEDIR"
mkdir -p "$INSTALL/.config/hypr/themes/templates" "$HOMEDIR/.local/bin" \
  "$HOMEDIR/.config/hypr/themes/solo/generated"

cp "$REPO/.local/bin/theme-apply-templates.sh" "$HOMEDIR/.local/bin/"
chmod +x "$HOMEDIR/.local/bin/theme-apply-templates.sh"
printf '#!/bin/sh\nexit 0\n' >"$HOMEDIR/.local/bin/hyprsimple-migrate.sh"
chmod +x "$HOMEDIR/.local/bin/hyprsimple-migrate.sh"
printf 'background = "#2d353b"\nforeground = "#d3c6aa"\n' \
  >"$HOMEDIR/.config/hypr/themes/solo/colors.toml"
ln -sfn "$HOMEDIR/.config/hypr/themes/solo/generated/hyprland-colors.lua" \
  "$HOMEDIR/.config/hypr/theme-active.lua"

printf '@define-color wl_background {{ background }};\n' \
  >"$INSTALL/.config/hypr/themes/templates/hyprlock.conf.tpl"

# The fixture must be in the state these checks assume before any of them runs.
# Five checks in this repository have passed against a fixture that was not what
# it claimed, so this is asserted rather than trusted.
if [[ -f $HOMEDIR/.config/hypr/themes/solo/generated/hyprlock.conf ]]; then
  printf 'not ok - fixture already has rendered output before the first run\n' >&2
  exit 1
fi

run_update() {
  HOME="$HOMEDIR" HYPRSIMPLE_PATH="$INSTALL" PATH="$STUB:$PATH" \
    bash "$REPO/.local/bin/hyprsimple-update.sh" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

run_update
check "an unrendered template is rendered by the update" \
  "$(grep -c 'wl_background #2d353b' "$HOMEDIR/.config/hypr/themes/solo/generated/hyprlock.conf" 2>/dev/null)" "1"
check "and the active theme's output reaches the lock screen" \
  "$(grep -c 'wl_background #2d353b' "$HOMEDIR/.config/hypr/theme-hyprlock.conf" 2>/dev/null)" "1"

marker="$HOMEDIR/.config/hypr/themes/solo/generated/hyprlock.conf"
printf '/* touched by hand */\n' >>"$marker"
run_update
check "an unchanged template does not trigger a re-render" \
  "$(grep -c 'touched by hand' "$marker")" "1"

printf '@define-color wl_background {{ background }};\n@define-color wl_extra {{ foreground }};\n' \
  >"$INSTALL/.config/hypr/themes/templates/hyprlock.conf.tpl"
run_update
check "a changed template triggers a re-render" \
  "$(grep -c 'wl_extra #d3c6aa' "$marker")" "1"
check "and the hand edit is gone, because rendering is the source of truth" \
  "$(grep -c 'touched by hand' "$marker")" "0"

# This is the case that cost a second migration: shipping a template is not
# delivering it unless something renders.

printf 'X {{ background }}\n' >"$INSTALL/.config/hypr/themes/templates/brand-new.tpl"
run_update
check "a newly shipped template reaches an existing theme with no migration" \
  "$(grep -c 'X #2d353b' "$HOMEDIR/.config/hypr/themes/solo/generated/brand-new" 2>/dev/null)" "1"

check "the update still exits 0" "$(cat "$TMP/rc")" "0"

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
