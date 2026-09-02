#!/bin/bash
# Checks the migration that converts an existing install's rofi configs into
# import stubs. Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788239161.sh"
FIXTURES="$REPO/test/fixtures/rofi"
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

RELS=(config.rasi confirm.rasi font.rasi keybindings/style.rasi theme-picker/style.rasi)

# A home as it looked before the split: the pre-split files, pinned in
# test/fixtures/rofi, plus the theme-owned paths the migration must not touch.
make_home() {
  local home="$1"
  must_be_fixture "$home"
  mkdir -p "$home/.config/rofi/keybindings" "$home/.config/rofi/theme-picker" \
    "$home/.config/rofi/launcher" "$home/.config/rofi/powermenu"
  local rel
  for rel in "${RELS[@]}"; do
    cp "$FIXTURES/$rel" "$home/.config/rofi/$rel"
  done
  printf '/* theme owned */\n' >"$home/.config/rofi/launcher/style.rasi"
  printf '/* theme owned */\n' >"$home/.config/rofi/powermenu/style.rasi"
  printf '* { background: #000000FF; }\n' >"$home/.config/rofi/rofi-colors.rasi"
}

home="$TMP/pristine"
make_home "$home"
HOME="$home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/out" 2>&1

for rel in "${RELS[@]}"; do
  check "pristine $rel becomes the shipped stub" \
    "$(cmp -s "$home/.config/rofi/$rel" "$REPO/.config/rofi/$rel" && echo same || echo different)" "same"
done

check "the hyprsimple link is created" \
  "$([[ -L $home/.config/rofi/hyprsimple ]] && echo yes || echo no)" "yes"
check "the link resolves to the install's defaults" \
  "$([[ -f $home/.config/rofi/hyprsimple/config.rasi ]] && echo yes || echo no)" "yes"

check "launcher/style.rasi is untouched" \
  "$(md5sum <"$home/.config/rofi/launcher/style.rasi" | cut -d' ' -f1)" \
  "$(printf '/* theme owned */\n' | md5sum | cut -d' ' -f1)"
check "powermenu/style.rasi is untouched" \
  "$(md5sum <"$home/.config/rofi/powermenu/style.rasi" | cut -d' ' -f1)" \
  "$(printf '/* theme owned */\n' | md5sum | cut -d' ' -f1)"
check "rofi-colors.rasi is untouched" \
  "$(md5sum <"$home/.config/rofi/rofi-colors.rasi" | cut -d' ' -f1)" \
  "$(printf '* { background: #000000FF; }\n' | md5sum | cut -d' ' -f1)"

before=$(find "$home/.config/rofi" -type f -exec md5sum {} + | sort | md5sum)
HOME="$home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >/dev/null 2>&1
after=$(find "$home/.config/rofi" -type f -exec md5sum {} + | sort | md5sum)
check "a second run is a no-op" "$after" "$before"

edited="$TMP/edited"
make_home "$edited"
printf '\n/* a users own comment */\n' >>"$edited/.config/rofi/config.rasi"
edited_before=$(md5sum "$edited/.config/rofi/config.rasi" | cut -d' ' -f1)
HOME="$edited" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/edited_out" 2>&1
check "an edited file is byte-identical after the migration" \
  "$(md5sum "$edited/.config/rofi/config.rasi" | cut -d' ' -f1)" "$edited_before"
check "the user is told how to convert it" \
  "$(grep -c 'hyprsimple-refresh-config.sh rofi/config.rasi' "$TMP/edited_out")" "1"
check "an edited file does not stop the others converting" \
  "$(cmp -s "$edited/.config/rofi/font.rasi" "$REPO/.config/rofi/font.rasi" && echo same || echo different)" "same"

bare="$TMP/bare"
must_be_fixture "$bare"
mkdir -p "$bare/.config"
HOME="$bare" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >/dev/null 2>&1
check "a home without rofi exits clean" "$?" "0"

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
