#!/bin/bash
# Checks the dunst drop-in migration and theme-switcher.sh against fixtures.
# Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788065734.sh"
SWITCHER="$REPO/.local/bin/theme-switcher.sh"
TEMPLATER="$REPO/.local/bin/theme-apply-templates.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# Every fixture home goes through this before a migration or theme-switcher
# run touches it. An empty path would make later rm/cp calls operate against
# the real $HOME, which is the environment this suite runs in.
must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'fixture: refusing to use path [%s], expected a path under %s\n' "${1:-}" "$TMP" >&2
    exit 2
  fi
}

# Builds a dunstrc with the given colour values in each section, plus one
# fixed, non-colour line ("timeout = $5") so a caller can check that edit
# survives the migration untouched.
build_dunstrc() {
  local path="$1"
  local frame="$2"
  local bg="$3"
  local fg="$4"
  local timeout="$5"
  cat >"$path" <<EOF
[global]
    follow = mouse
    frame_color = "$frame"
    timeout = $timeout

[urgency_low]
    background = "$bg"
    foreground = "$fg"

[urgency_normal]
    background = "$bg"
    foreground = "$fg"

[urgency_critical]
    background = "$bg"
    foreground = "$fg"
    frame_color = "$frame"
EOF
}

SHIPPED_FRAME='#a6adc8'
SHIPPED_BG='#1e1e2e'
SHIPPED_FG='#cdd6f4'
SHIPPED_TIMEOUT=5

# ---- theme-switcher.sh contains no sed against DUNST_CONFIG --------------

if grep -q 'sed -i.*DUNST_CONFIG' "$SWITCHER"; then
  fail "theme-switcher.sh no longer sed-patches DUNST_CONFIG"
else
  pass "theme-switcher.sh no longer sed-patches DUNST_CONFIG"
fi

# ---- theme-switcher.sh drops in a theme's generated/dunst-colors --------

switch_home="$TMP/switch-home"
must_be_fixture "$switch_home"
mkdir -p "$switch_home/.local/bin" "$switch_home/.config/hypr"
cp "$REPO/.local/bin/hypr-helpers.sh" "$switch_home/.local/bin/hypr-helpers.sh"

withcolors="$switch_home/.config/hypr/themes/withcolors"
mkdir -p "$withcolors/generated"
cat >"$withcolors/generated/dunst-colors" <<'EOF'
[global]
    frame_color = "#bac2de"

[urgency_low]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#bac2de"

[urgency_normal]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#89b4fa"

[urgency_critical]
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    frame_color = "#f38ba8"
EOF

THEME_SWITCHER_NO_RELOAD=1 HOME="$switch_home" bash "$SWITCHER" withcolors \
  >"$TMP/switch_out" 2>&1
check "theme-switcher exits 0 for a theme with generated/dunst-colors" "$?" "0"

DROPIN="$switch_home/.config/dunst/dunstrc.d/90-theme.conf"
if cmp -s "$DROPIN" "$withcolors/generated/dunst-colors"; then
  pass "the drop-in is byte-identical to generated/dunst-colors"
else
  fail "the drop-in is byte-identical to generated/dunst-colors"
fi

# ---- switching to a theme with no colours removes the drop-in -----------

nocolors="$switch_home/.config/hypr/themes/nocolors"
mkdir -p "$nocolors"

THEME_SWITCHER_NO_RELOAD=1 HOME="$switch_home" bash "$SWITCHER" nocolors \
  >"$TMP/switch_out2" 2>&1
check "theme-switcher exits 0 for a theme with no colours" "$?" "0"

check "switching to a colourless theme removes the drop-in" \
  "$([[ -e $DROPIN ]] && echo present || echo gone)" gone

# ---- theme-apply-templates.sh renders a [global] frame_color ------------

tpl_home="$TMP/template-home"
must_be_fixture "$tpl_home"
mkdir -p "$tpl_home/.config/hypr/themes/templates"
cp "$REPO/.config/hypr/themes/templates/dunst-colors.tpl" \
  "$tpl_home/.config/hypr/themes/templates/"

tpl_theme="$TMP/template-theme"
mkdir -p "$tpl_theme"
cat >"$tpl_theme/colors.toml" <<'EOF'
accent = "#89b4fa"
background = "#1e1e2e"
foreground = "#cdd6f4"
color1 = "#f38ba8"
color7 = "#bac2de"
EOF

HOME="$tpl_home" bash "$TEMPLATER" "$tpl_theme" >"$TMP/tpl_out" 2>&1
check "theme-apply-templates.sh exits 0" "$?" "0"

rendered="$tpl_theme/generated/dunst-colors"
if grep -q '^\[global\]' "$rendered" && grep -A1 '^\[global\]' "$rendered" | grep -q 'frame_color'; then
  pass "the rendered template has a [global] section with frame_color"
else
  fail "the rendered template has a [global] section with frame_color"
fi

# ---- migration: plain colour drift resets to the shipped default --------

inst="$TMP/install-plain"
mig_home="$TMP/home-plain"
must_be_fixture "$mig_home"
mkdir -p "$inst/.config/dunst" "$mig_home/.config/dunst"
build_dunstrc "$inst/.config/dunst/dunstrc" "$SHIPPED_FRAME" "$SHIPPED_BG" "$SHIPPED_FG" "$SHIPPED_TIMEOUT"
build_dunstrc "$mig_home/.config/dunst/dunstrc" '#ffcc00' '#111111' '#eeeeee' "$SHIPPED_TIMEOUT"

HOME="$mig_home" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >"$TMP/mig_out" 2>&1
check "migration exits 0" "$?" "0"

if cmp -s "$mig_home/.config/dunst/dunstrc" "$inst/.config/dunst/dunstrc"; then
  pass "dunstrc is reset to the shipped default"
else
  fail "dunstrc is reset to the shipped default"
fi

check "the drop-in carries the pre-migration colours" \
  "$(grep -c 'frame_color = "#ffcc00"' "$mig_home/.config/dunst/dunstrc.d/90-theme.conf" 2>/dev/null)" "2"

# ---- a second run changes nothing, and writes no second backup ----------

snap=$(find "$mig_home" -type f -exec md5sum {} + | sort)
HOME="$mig_home" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
check "migration is idempotent" "$(find "$mig_home" -type f -exec md5sum {} + | sort)" "$snap"

check "a second run writes no second backup" \
  "$(find "$mig_home/.config/dunst" -maxdepth 1 -name 'dunstrc.bak.*' | wc -l)" "1"

# ---- a non-colour edit survives the migration ----------------------------

edit_inst="$TMP/install-edit"
edit_home="$TMP/home-edit"
must_be_fixture "$edit_home"
mkdir -p "$edit_inst/.config/dunst" "$edit_home/.config/dunst"
build_dunstrc "$edit_inst/.config/dunst/dunstrc" "$SHIPPED_FRAME" "$SHIPPED_BG" "$SHIPPED_FG" "$SHIPPED_TIMEOUT"
build_dunstrc "$edit_home/.config/dunst/dunstrc" '#ffcc00' '#111111' '#eeeeee' 45

HOME="$edit_home" HYPRSIMPLE_PATH="$edit_inst" bash "$MIGRATION" >/dev/null 2>&1
if grep -q 'timeout = 45' "$edit_home/.config/dunst/dunstrc"; then
  pass "a non-colour edit survives the migration"
else
  fail "a non-colour edit survives the migration"
fi

# ---- a missing dunstrc is a no-op ----------------------------------------

HOME="$TMP/nothing" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
check "a missing dunstrc exits 0" "$?" "0"

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
