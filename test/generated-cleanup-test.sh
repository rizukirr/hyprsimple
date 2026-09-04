#!/bin/bash
# Rendering only ever wrote, so an output whose template was removed stayed in
# every theme forever. Dropping the wlogout power menu left wlogout-colors.css
# in all sixteen themes with nothing left to read it.
#
# The dangerous half of the fix is the deleting, not the rendering, so the
# guard gets as many checks as the feature: an empty template directory must
# leave everything alone rather than empty every theme.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RENDERER="$REPO/.local/bin/theme-apply-templates.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
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

# One fixture install and one theme, rebuilt for each case so no case inherits
# another's leftovers.
setup() {
  INSTALL="$TMP/install"
  HOMEDIR="$TMP/home"
  must_be_fixture "$INSTALL"
  must_be_fixture "$HOMEDIR"
  rm -rf "$INSTALL" "$HOMEDIR"
  THEME="$HOMEDIR/.config/hypr/themes/solo"
  mkdir -p "$INSTALL/.config/hypr/themes/templates" "$THEME/generated"
  printf 'background = "#2d353b"\n' >"$THEME/colors.toml"
  printf 'bg {{ background }}\n' >"$INSTALL/.config/hypr/themes/templates/kept.tpl"
}

render() {
  HOME="$HOMEDIR" HYPRSIMPLE_PATH="$INSTALL" bash "$RENDERER" "$THEME" >/dev/null 2>&1
}

# ---- the orphan is removed ----------------------------------------------

setup
printf 'stale\n' >"$THEME/generated/gone.css"
render
check "an output whose template was removed is deleted" \
  "$([[ -f $THEME/generated/gone.css ]] && echo present || echo removed)" "removed"
check "and an output that still has a template survives" \
  "$(grep -c 'bg #2d353b' "$THEME/generated/kept" 2>/dev/null)" "1"

# ---- a user's own template counts as a template --------------------------

setup
mkdir -p "$HOMEDIR/.config/hypr/themes/templates.user"
printf 'mine {{ background }}\n' >"$HOMEDIR/.config/hypr/themes/templates.user/mine.conf.tpl"
render
check "an output from the user's own template is not treated as an orphan" \
  "$(grep -c 'mine #2d353b' "$THEME/generated/mine.conf" 2>/dev/null)" "1"

# ---- the guard -----------------------------------------------------------
#
# This is the case that decides whether the feature is safe. With no templates
# to render, the expected set is empty, and reconciling against an empty set
# would delete every generated file in the theme.

setup
rm -f "$INSTALL/.config/hypr/themes/templates"/*.tpl
printf 'precious\n' >"$THEME/generated/kept"
printf 'precious\n' >"$THEME/generated/gone.css"
render
check "an empty template directory deletes nothing" \
  "$(find "$THEME/generated" -type f | wc -l)" "2"

setup
rm -rf "$INSTALL/.config/hypr/themes/templates"
printf 'precious\n' >"$THEME/generated/kept"
render
check "a missing template directory deletes nothing" \
  "$(find "$THEME/generated" -type f | wc -l)" "1"

# ---- a theme with no colors.toml is never touched -------------------------

setup
rm -f "$THEME/colors.toml"
printf 'precious\n' >"$THEME/generated/gone.css"
render
check "a theme with no colors.toml keeps its generated files" \
  "$([[ -f $THEME/generated/gone.css ]] && echo present || echo removed)" "present"

# ---- idempotent ----------------------------------------------------------

setup
printf 'stale\n' >"$THEME/generated/gone.css"
render
first="$(find "$THEME/generated" -type f | sort | tr '\n' ' ')"
render
check "a second render changes nothing" \
  "$(find "$THEME/generated" -type f | sort | tr '\n' ' ')" "$first"

# ---- the migration delivers it -------------------------------------------

# Pinned by name, not "the newest", which points somewhere else the moment
# another migration lands.
MIGRATION="$REPO/migrations/1788532937.sh"
if [[ -f $MIGRATION ]]; then
  pass "the migration this suite tests exists"
else
  fail "$MIGRATION is missing, so every check below is testing nothing"
fi

setup
mkdir -p "$HOMEDIR/.local/bin"
cp "$RENDERER" "$HOMEDIR/.local/bin/theme-apply-templates.sh"
chmod +x "$HOMEDIR/.local/bin/theme-apply-templates.sh"
printf 'stale\n' >"$THEME/generated/gone.css"
out="$(HOME="$HOMEDIR" HYPRSIMPLE_PATH="$INSTALL" bash "$MIGRATION" 2>&1)"
check "the migration removes the orphan" \
  "$([[ -f $THEME/generated/gone.css ]] && echo present || echo removed)" "removed"
check "the migration says how many it removed" \
  "$(printf '%s' "$out" | grep -c 'Removed 1 stale')" "1"

# A second run has nothing left to remove and must say nothing about it.
out="$(HOME="$HOMEDIR" HYPRSIMPLE_PATH="$INSTALL" bash "$MIGRATION" 2>&1)"
check "re-running the migration reports no removals" \
  "$(printf '%s' "$out" | grep -c 'stale file')" "0"

# The migration must delegate every deletion to the renderer, so that it cannot
# disagree with the rule it is delivering. Pointing it at a renderer that does
# nothing is what proves that: if the migration deletes anything of its own,
# the orphan disappears here.
#
# An earlier version of this block removed the renderer entirely instead. That
# passed with the migration's guard deleted, because a renderer that is not
# there fails and the loop skips the theme either way, so it was testing
# nothing.
setup
mkdir -p "$HOMEDIR/.local/bin"
printf '#!/bin/sh\nexit 0\n' >"$HOMEDIR/.local/bin/theme-apply-templates.sh"
chmod +x "$HOMEDIR/.local/bin/theme-apply-templates.sh"
printf 'stale\n' >"$THEME/generated/gone.css"
HOME="$HOMEDIR" HYPRSIMPLE_PATH="$INSTALL" bash "$MIGRATION" >/dev/null 2>&1
check "the migration deletes nothing itself, only what the renderer removed" \
  "$([[ -f $THEME/generated/gone.css ]] && echo present || echo removed)" "present"

setup
printf 'stale\n' >"$THEME/generated/gone.css"
HOME="$HOMEDIR" HYPRSIMPLE_PATH="$INSTALL" bash "$MIGRATION" >/dev/null 2>&1
rc=$?
check "with no renderer installed the migration exits 0 and leaves the theme alone" \
  "$rc:$([[ -f $THEME/generated/gone.css ]] && echo present || echo removed)" "0:present"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
