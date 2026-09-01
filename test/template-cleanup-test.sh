#!/bin/bash
# Checks the migration that removes the unread copy of the theme templates,
# and only when every file in it is one this project shipped.
# Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788278344.sh"
SHIPPED="$REPO/.config/hypr/themes/templates"
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

# The templates as they were when this migration was written, not as they are
# now. This fixture stands in for a home that predates the delivery change, and
# such a home cannot contain a template added afterwards. Copying the current
# set instead makes the suite fail the moment a template is added, which is a
# fixture bug rather than a regression.
CLEANUP_COMMIT=$(git -C "$REPO" log --diff-filter=A --format=%H -- migrations/1788278344.sh | tail -1)
if [[ -z $CLEANUP_COMMIT ]]; then
  printf 'not ok - could not find the commit that added the migration\n' >&2
  exit 1
fi

new_home() {
  HOMEDIR="$TMP/$1"
  must_be_fixture "$HOMEDIR"
  TPL="$HOMEDIR/.config/hypr/themes/templates"
  mkdir -p "$TPL"
  while IFS= read -r rel; do
    git -C "$REPO" show "$CLEANUP_COMMIT:$rel" >"$TPL/$(basename "$rel")"
  done < <(git -C "$REPO" ls-tree --name-only "$CLEANUP_COMMIT" .config/hypr/themes/templates/ | grep '\.tpl$')
  # A fixture that did not populate must fail loudly rather than let a later
  # check pass against an empty directory.
  if [[ $(ls "$TPL" | wc -l) -eq 0 ]]; then
    printf 'not ok - fixture templates did not copy (%s)\n' "$1" >&2
    exit 1
  fi
}

run() { HOME="$HOMEDIR" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/out" 2>&1; }

# --- 1. a directory of untouched shipped templates is removed --------------

new_home pristine
run
check "a directory of shipped templates is removed" \
  "$([[ -d $TPL ]] && echo present || echo gone)" "gone"

# --- 2. a re-run is a no-op ------------------------------------------------

run
check "a second run exits 0 with the directory already gone" "$?" "0"

# --- 3. one customised file protects the whole directory ------------------

new_home customised
printf '/* mine */\n' >>"$TPL/waybar-colors.css.tpl"
before=$(find "$TPL" -type f -exec md5sum {} + | sort | md5sum)
run
check "a customised template stops the removal" \
  "$([[ -d $TPL ]] && echo present || echo gone)" "present"
check "and nothing in the directory is touched" \
  "$(find "$TPL" -type f -exec md5sum {} + | sort | md5sum)" "$before"
check "and the user is told where to move it" \
  "$(grep -c 'templates.user' "$TMP/out")" "1"
check "and the offending file is named" \
  "$(grep -c 'waybar-colors.css.tpl' "$TMP/out")" "1"

# --- 4. a file the user added protects the directory too ------------------

new_home added
printf '/* mine */\n' >"$TPL/my-own.tpl"
run
check "an added file stops the removal" \
  "$([[ -d $TPL ]] && echo present || echo gone)" "present"

# --- 5. an older shipped version still counts as ours ---------------------
#
# The point of carrying history rather than only the current checksum: a home
# that never took a template update holds an old version, which is still not
# the user's work.

new_home stale
old=$(git -C "$REPO" log --format=%H -- .config/hypr/themes/templates/dunst-colors.tpl | tail -1)
git -C "$REPO" show "$old:.config/hypr/themes/templates/dunst-colors.tpl" >"$TPL/dunst-colors.tpl"
run
check "an older shipped version does not block removal" \
  "$([[ -d $TPL ]] && echo present || echo gone)" "gone"

# --- 6. a home without the directory at all -------------------------------

HOMEDIR="$TMP/nodir"
must_be_fixture "$HOMEDIR"
mkdir -p "$HOMEDIR/.config"
run
check "a home without the directory exits 0" "$?" "0"

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
