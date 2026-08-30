#!/bin/bash
# Checks the dunst drop-in migration and theme-switcher.sh against fixtures.
# Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788065734.sh"
MIGRATION2="$REPO/migrations/1788066582.sh"
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
# survives the migration untouched. $6 is the urgency_critical frame_color,
# which hyprsimple ships distinct from the [global] one; it defaults to $2 so
# fixtures that only care about drift can keep passing five args.
build_dunstrc() {
  local path="$1"
  local frame="$2"
  local bg="$3"
  local fg="$4"
  local timeout="$5"
  local critframe="${6:-$frame}"
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
    frame_color = "$critframe"
EOF
}

SHIPPED_FRAME='#a6adc8'
SHIPPED_BG='#1e1e2e'
SHIPPED_FG='#CDD6F4'
SHIPPED_CRIT_FRAME='#FAB387'
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
build_dunstrc "$inst/.config/dunst/dunstrc" "$SHIPPED_FRAME" "$SHIPPED_BG" "$SHIPPED_FG" "$SHIPPED_TIMEOUT" "$SHIPPED_CRIT_FRAME"
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
build_dunstrc "$edit_inst/.config/dunst/dunstrc" "$SHIPPED_FRAME" "$SHIPPED_BG" "$SHIPPED_FG" "$SHIPPED_TIMEOUT" "$SHIPPED_CRIT_FRAME"
build_dunstrc "$edit_home/.config/dunst/dunstrc" '#ffcc00' '#111111' '#eeeeee' 45

HOME="$edit_home" HYPRSIMPLE_PATH="$edit_inst" bash "$MIGRATION" >/dev/null 2>&1
if grep -q 'timeout = 45' "$edit_home/.config/dunst/dunstrc"; then
  pass "a non-colour edit survives the migration"
else
  fail "a non-colour edit survives the migration"
fi

# ---- colours reset even when the shipped install's dunstrc is comment-only,
# the state Task 3 ships. A migration is a fixed point in history and must not
# depend on a path a later commit is free to repurpose. --------------------

comment_inst="$TMP/install-comment"
comment_home="$TMP/home-comment"
must_be_fixture "$comment_home"
mkdir -p "$comment_inst/.config/dunst" "$comment_home/.config/dunst"
cat >"$comment_inst/.config/dunst/dunstrc" <<'EOF'
# See dunstrc.d/ for hyprsimple's dunst colours.
EOF
build_dunstrc "$comment_home/.config/dunst/dunstrc" '#ffcc00' '#111111' '#eeeeee' "$SHIPPED_TIMEOUT" '#ffcc00'

HOME="$comment_home" HYPRSIMPLE_PATH="$comment_inst" bash "$MIGRATION" >/dev/null 2>&1
if grep -q "frame_color = \"$SHIPPED_FRAME\"" "$comment_home/.config/dunst/dunstrc" \
  && grep -q "foreground = \"$SHIPPED_FG\"" "$comment_home/.config/dunst/dunstrc"; then
  pass "colours reset even when the shipped install's dunstrc is comment-only"
else
  fail "colours reset even when the shipped install's dunstrc is comment-only"
fi

# ---- a colour key in a section hyprsimple shipped none for is left alone --

extra_inst="$TMP/install-extra"
extra_home="$TMP/home-extra"
must_be_fixture "$extra_home"
mkdir -p "$extra_inst/.config/dunst" "$extra_home/.config/dunst"
build_dunstrc "$extra_inst/.config/dunst/dunstrc" "$SHIPPED_FRAME" "$SHIPPED_BG" "$SHIPPED_FG" "$SHIPPED_TIMEOUT" "$SHIPPED_CRIT_FRAME"
cat >"$extra_home/.config/dunst/dunstrc" <<EOF
[global]
    follow = mouse
    frame_color = "#ffcc00"
    timeout = $SHIPPED_TIMEOUT

[urgency_low]
    background = "#111111"
    foreground = "#eeeeee"
    frame_color = "#89b4fa"

[urgency_normal]
    background = "#111111"
    foreground = "#eeeeee"

[urgency_critical]
    background = "#111111"
    foreground = "#eeeeee"
    frame_color = "#ffcc00"
EOF

HOME="$extra_home" HYPRSIMPLE_PATH="$extra_inst" bash "$MIGRATION" >/dev/null 2>&1
if grep -q 'frame_color = "#89b4fa"' "$extra_home/.config/dunst/dunstrc"; then
  pass "a colour key in a section hyprsimple shipped none for survives the migration"
else
  fail "a colour key in a section hyprsimple shipped none for survives the migration"
fi

# ---- migration 2: an unedited dunstrc is replaced by the base -----------
# HYPRSIMPLE_PATH points at the repo itself: the migration only reads from it,
# and this is what proves the checks hold against what hyprsimple actually
# ships, not a stand-in.

unedited_home="$TMP/home-move-unedited"
must_be_fixture "$unedited_home"
mkdir -p "$unedited_home/.config/dunst"
git -C "$REPO" show 12d5e47:.config/dunst/dunstrc >"$unedited_home/.config/dunst/dunstrc"

HOME="$unedited_home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION2" >"$TMP/mig2_out" 2>&1
check "migration 2 exits 0 for an unedited dunstrc" "$?" "0"

if cmp -s "$unedited_home/.config/dunst/dunstrc" "$REPO/.config/dunst/dunstrc"; then
  pass "an unedited dunstrc is replaced by the base"
else
  fail "an unedited dunstrc is replaced by the base"
fi

check "no .pre-split file exists for an unedited dunstrc" \
  "$(find "$unedited_home/.config/dunst" -maxdepth 1 -name 'dunstrc.pre-split.*' | wc -l)" "0"

hyprsimple_link="$unedited_home/.config/dunst/dunstrc.d/10-hyprsimple.conf"
readlink -e "$hyprsimple_link" >"$TMP/link_target"
check "readlink -e on dunstrc.d/10-hyprsimple.conf exits 0" "$?" "0"
check "dunstrc.d/10-hyprsimple.conf names the file under the install fixture" \
  "$(cat "$TMP/link_target")" "$REPO/default/dunst/10-hyprsimple.conf"

check "99-user.conf exists after the run" \
  "$([[ -f $unedited_home/.config/dunst/dunstrc.d/99-user.conf ]] && echo yes || echo no)" "yes"

# ---- migration 2: an edited dunstrc is kept, its differences copied out --

edited_home="$TMP/home-move-edited"
must_be_fixture "$edited_home"
mkdir -p "$edited_home/.config/dunst"
git -C "$REPO" show 12d5e47:.config/dunst/dunstrc \
  | sed 's/frame_color = "#a6adc8"/frame_color = "#ffcc00"/' \
  >"$edited_home/.config/dunst/dunstrc"
cp "$edited_home/.config/dunst/dunstrc" "$TMP/edited_original"

HOME="$edited_home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION2" >/dev/null 2>&1
check "migration 2 exits 0 for an edited dunstrc" "$?" "0"

kept="$(find "$edited_home/.config/dunst" -maxdepth 1 -name 'dunstrc.pre-split.*')"
if [[ -n $kept ]] && cmp -s "$kept" "$TMP/edited_original"; then
  pass "an edited dunstrc produces a .pre-split file byte-identical to the original"
else
  fail "an edited dunstrc produces a .pre-split file byte-identical to the original"
fi

if grep -q 'frame_color = "#ffcc00"' "$edited_home/.config/dunst/dunstrc.d/99-user.conf"; then
  pass "99-user.conf contains the edited key"
else
  fail "99-user.conf contains the edited key"
fi

HOME="$edited_home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION2" >/dev/null 2>&1
check "a second run creates no additional .pre-split file" \
  "$(find "$edited_home/.config/dunst" -maxdepth 1 -name 'dunstrc.pre-split.*' | wc -l)" "1"

# ---- migration 2: 99-user.conf written by an earlier run is untouched ---

preserve_home="$TMP/home-move-preserve"
must_be_fixture "$preserve_home"
mkdir -p "$preserve_home/.config/dunst/dunstrc.d"
git -C "$REPO" show 12d5e47:.config/dunst/dunstrc >"$preserve_home/.config/dunst/dunstrc"
echo "# MARKER-DO-NOT-OVERWRITE" >"$preserve_home/.config/dunst/dunstrc.d/99-user.conf"

HOME="$preserve_home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION2" >/dev/null 2>&1
if grep -q 'MARKER-DO-NOT-OVERWRITE' "$preserve_home/.config/dunst/dunstrc.d/99-user.conf"; then
  pass "99-user.conf written by an earlier run is not overwritten"
else
  fail "99-user.conf written by an earlier run is not overwritten"
fi

# ---- a missing dunstrc is a no-op ----------------------------------------

HOME="$TMP/nothing" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
check "a missing dunstrc exits 0" "$?" "0"

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
