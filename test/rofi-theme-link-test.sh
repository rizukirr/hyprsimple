#!/bin/bash
# install.sh carried two lines meant to point the rofi directories at the
# active theme:
#
#   ln -sfn "$THEME_DIR/rofi/launcher"  "$HOME/.config/rofi/launcher"
#   ln -sfn "$THEME_DIR/rofi/powermenu" "$HOME/.config/rofi/powermenu"
#
# Both halves were wrong, independently.
#
# By the time they ran, ~/.config/rofi/launcher was a real directory, copied
# from the repository's .config/rofi a few hundred lines earlier. `ln -s` given
# an existing directory writes the link inside it rather than replacing it, so
# what actually appeared was ~/.config/rofi/launcher/launcher.
#
# And no theme has ever shipped a rofi/ directory. All sixteen lack one. So the
# target did not exist and the link dangled from the moment it was created.
#
# Measured on the maintainer's machine before the fix:
#   ~/.config/rofi/launcher/launcher  -> .../themes/deep-sea/rofi/launcher  BROKEN
#   ~/.config/rofi/powermenu/powermenu -> .../themes/deep-sea/rofi/powermenu BROKEN
#
# Both pointed at deep-sea, the install-time default, while the active theme was
# rosepine. Nothing read them. theme-switcher.sh themes rofi by writing images/
# and patching style.rasi inside the real directories.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788620441.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the lines are gone from install.sh -------------------------------------

check "install.sh no longer links rofi/launcher at a theme" \
  "$(grep -c 'ln -sfn "\$THEME_DIR/rofi/launcher"' "$REPO/install.sh")" "0"
check "install.sh no longer links rofi/powermenu at a theme" \
  "$(grep -c 'ln -sfn "\$THEME_DIR/rofi/powermenu"' "$REPO/install.sh")" "0"

# The links it does still make are the ones that work, so this is not a check
# that install.sh stopped linking anything at all.
check "the hyprsimple defaults link is still made" \
  "$(grep -c 'ln -sfn "\$HYPRSIMPLE_PATH/default/rofi" "\$HOME/.config/rofi/hyprsimple"' "$REPO/install.sh")" "1"

# --- no shipped theme has the directory those lines pointed at ---------------

themes=0; with_rofi=0
for theme in "$REPO/.config/hypr/themes"/*/; do
  [[ -d $theme ]] || continue
  themes=$((themes + 1))
  [[ -d $theme/rofi ]] && with_rofi=$((with_rofi + 1))
done
if (( themes < 5 )); then
  fail "found only $themes themes, so this check is not looking at the real set"
else
  pass "checked $themes shipped themes"
fi
check "no shipped theme has a rofi directory, which is what made the link dangle" \
  "$with_rofi" "0"

# --- the migration removes what earlier installs already have ----------------

mk_home() {
  rm -rf "$TMP/home"
  mkdir -p "$TMP/home/.config/rofi/launcher" "$TMP/home/.config/rofi/powermenu"
  mkdir -p "$TMP/home/.config/hypr/themes/deep-sea"
  # The real directories carry real files, as they do on a live install.
  printf 'x\n' >"$TMP/home/.config/rofi/launcher/style.rasi"
  printf 'x\n' >"$TMP/home/.config/rofi/powermenu/style.rasi"
}
migration_rc=0
run_migration() {
  HOME="$TMP/home" bash "$MIGRATION" >"$TMP/out" 2>&1
  migration_rc=$?
}

# The exact shape a pre-fix install leaves behind.
mk_home
ln -sfn "$TMP/home/.config/hypr/themes/deep-sea/rofi/launcher" "$TMP/home/.config/rofi/launcher/launcher"
ln -sfn "$TMP/home/.config/hypr/themes/deep-sea/rofi/powermenu" "$TMP/home/.config/rofi/powermenu/powermenu"
check "the fixture reproduces the bug: the launcher link is broken" \
  "$([[ -L $TMP/home/.config/rofi/launcher/launcher && ! -e $TMP/home/.config/rofi/launcher/launcher ]] && echo broken || echo no)" "broken"

run_migration
check "the migration removes the launcher link" \
  "$([[ -e $TMP/home/.config/rofi/launcher/launcher || -L $TMP/home/.config/rofi/launcher/launcher ]] && echo present || echo gone)" "gone"
check "and the powermenu link" \
  "$([[ -e $TMP/home/.config/rofi/powermenu/powermenu || -L $TMP/home/.config/rofi/powermenu/powermenu ]] && echo present || echo gone)" "gone"
check "and leaves the real files alone" \
  "$([[ -f $TMP/home/.config/rofi/launcher/style.rasi ]] && echo kept || echo lost)" "kept"
check "and reports both" "$(grep -c '^  Removed ' "$TMP/out")" "2"

run_migration
check "re-running reports nothing" "$(grep -c '^  Removed ' "$TMP/out")" "0"
check "and still exits 0" "$migration_rc" "0"

# --- what it must not touch --------------------------------------------------

mk_home
mkdir -p "$TMP/home/.config/hypr/themes/deep-sea/rofi/launcher"
ln -sfn "$TMP/home/.config/hypr/themes/deep-sea/rofi/launcher" "$TMP/home/.config/rofi/launcher/launcher"
run_migration
check "a link that does resolve is left alone" \
  "$([[ -L $TMP/home/.config/rofi/launcher/launcher ]] && echo kept || echo removed)" "kept"

mk_home
ln -sfn "$TMP/home/somewhere-else" "$TMP/home/.config/rofi/launcher/launcher"
run_migration
check "a broken link pointing somewhere else is left alone" \
  "$([[ -L $TMP/home/.config/rofi/launcher/launcher ]] && echo kept || echo removed)" "kept"

mk_home
mkdir -p "$TMP/home/.config/rofi/launcher/launcher"
run_migration
check "a real directory in that spot is left alone" \
  "$([[ -d $TMP/home/.config/rofi/launcher/launcher ]] && echo kept || echo removed)" "kept"

mk_home
run_migration
check "a home that never had the links removes nothing" \
  "$(grep -c '^  Removed ' "$TMP/out")" "0"
check "and exits 0" "$migration_rc" "0"
check "and prints only its title, as every migration does" \
  "$(wc -l <"$TMP/out")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
