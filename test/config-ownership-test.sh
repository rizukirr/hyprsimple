#!/bin/bash
# Every file hyprsimple ships under ~/.config is copied once and never touched
# again, and nothing in them said so. Several are the opposite: hyprpaper.conf
# is rewritten in full on every wallpaper change, theme-hyprlock.conf on every
# theme switch, and parts of ghostty/config and the two rofi style.rasi files
# are rewritten as well. Nothing said that either, so an edit to one of those
# was lost with no explanation.
#
# Each shipped config now opens by saying which of the two it is. This suite
# checks that the claim each file makes matches what the code actually does to
# it, so the headers cannot drift away from the truth.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788631500.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# The files the scripts rewrite. Each must say so rather than invite an edit.
REWRITTEN=(
  hypr/hyprpaper.conf
  hypr/theme-hyprlock.conf
  ghostty/config
  rofi/launcher/style.rasi
  rofi/powermenu/style.rasi
)
is_rewritten() {
  local f
  for f in "${REWRITTEN[@]}"; do [[ $1 == "$f" ]] && return 0; done
  return 1
}

# Config files a person edits by hand. Theme data, images and the strict-JSON
# .luarc.json are not configuration in this sense and are left out.
mapfile -t configs < <(
  find "$REPO/.config" -type f \
    ! -path '*/themes/*' ! -name '.luarc.json' ! -name '*.sh' |
    sed "s|$REPO/.config/||" | LC_ALL=C sort
)

if (( ${#configs[@]} < 15 )); then
  fail "found ${#configs[@]} config files, which is too few to be the real set"
else
  pass "checked ${#configs[@]} shipped config files"
fi

missing=(); wrong=()
for rel in "${configs[@]}"; do
  head_text=$(head -12 "$REPO/.config/$rel")
  if is_rewritten "$rel"; then
    # It may not tell someone their edits are safe when they are not.
    printf '%s' "$head_text" | grep -qiE 'do not edit|with one exception' ||
      wrong+=("$rel")
  else
    printf '%s' "$head_text" | grep -qiE 'is yours|Your |Override' || missing+=("$rel")
  fi
done

missing_str=""; (( ${#missing[@]} > 0 )) && missing_str="$(printf '%s; ' "${missing[@]}")"
check "every hand-edited config says it is yours" "$missing_str" ""

wrong_str=""; (( ${#wrong[@]} > 0 )) && wrong_str="$(printf '%s; ' "${wrong[@]}")"
check "every rewritten config says so instead" "$wrong_str" ""

# The list above has to match reality, or the two checks are graded against a
# wish. Each rewritten file must actually be written by something.
unproven=()
for rel in "${REWRITTEN[@]}"; do
  base=$(basename "$rel")
  grep -rqF "$base" "$REPO/.local/bin" "$REPO/install.sh" || unproven+=("$rel")
done
unproven_str=""; (( ${#unproven[@]} > 0 )) && unproven_str="$(printf '%s; ' "${unproven[@]}")"
check "every file called rewritten is named by a script that writes it" "$unproven_str" ""

# --- the migration delivers them to existing installs -----------------------

FIX="$REPO/test/fixtures/pre-headers"
mk_home() {
  rm -rf "${TMP:?}/mhome" "${TMP:?}/minstall"
  mkdir -p "$TMP/mhome/.config" "$TMP/minstall/.config"
  cp -r "$REPO/.config/." "$TMP/minstall/.config/"
  # A home holding the versions from before this change.
  for fixture in "$FIX"/*; do
    rel=$(basename "$fixture" | tr '_' '/')
    mkdir -p "$TMP/mhome/.config/$(dirname "$rel")"
    cp "$fixture" "$TMP/mhome/.config/$rel"
  done
}
run_migration() {
  HOME="$TMP/mhome" HYPRSIMPLE_PATH="$TMP/minstall" bash "$MIGRATION" >"$TMP/out" 2>&1
}

if [[ ! -d $FIX ]] || (( $(find "$FIX" -type f | wc -l) < 15 )); then
  fail "the pre-header fixtures are missing, so the migration is untested"
else
  pass "found $(find "$FIX" -type f | wc -l) pre-header fixtures"

  mk_home
  # The fixtures must genuinely differ from what is shipped now, or "updated"
  # below would be measuring nothing.
  differ=0
  for fixture in "$FIX"/*; do
    rel=$(basename "$fixture" | tr '_' '/')
    cmp -s "$fixture" "$REPO/.config/$rel" || differ=$((differ + 1))
  done
  check "every fixture differs from the file it is replaced by" \
    "$differ" "$(find "$FIX" -type f | wc -l | tr -d ' ')"

  run_migration
  updated=0
  for fixture in "$FIX"/*; do
    rel=$(basename "$fixture" | tr '_' '/')
    cmp -s "$TMP/mhome/.config/$rel" "$REPO/.config/$rel" && updated=$((updated + 1))
  done
  check "the migration updates every untouched file" \
    "$updated" "$(find "$FIX" -type f | wc -l | tr -d ' ')"
  check "and says nothing was skipped" "$(grep -c 'Left alone' "$TMP/out")" "0"

  run_migration
  check "re-running does nothing" "$(grep -c 'Nothing to do' "$TMP/out")" "1"

  # An edited file is left exactly as it was.
  mk_home
  printf '# my own dunstrc\n' >"$TMP/mhome/.config/dunst/dunstrc"
  run_migration
  check "an edited file is left alone" \
    "$(cat "$TMP/mhome/.config/dunst/dunstrc")" "# my own dunstrc"
  check "and is listed" "$(grep -c 'dunst/dunstrc' "$TMP/out")" "1"
  check "while the others still update" "$(grep -c 'Added the header' "$TMP/out")" "1"
fi

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
