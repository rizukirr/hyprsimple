#!/bin/bash
# Checks that a theme switch rewrites the rofi wallpaper reference and nothing
# else in style.rasi, and that the migration repairs files it already damaged.
#
# The rewrite was
#
#   sed -i "s|images/wallpaper\.[a-z]*|images/wallpaper.$WP_EXT|"
#
# and that pattern also matched the header of the same file, which says the
# line naming images/wallpaper.<ext> is the one exception and "Everything else
# here is kept". [a-z]* matched nothing before "<ext>", so every theme switch
# turned that into images/wallpaper.jpg<ext>. Found already done on a live
# machine, in both style.rasi files.
#
# Nothing here runs rofi or touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
MIGRATION="$REPO/migrations/1788790000.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}
for helper in pass fail check; do
  declare -F "$helper" >/dev/null || { printf 'not ok - helper %s missing\n' "$helper" >&2; exit 1; }
done

SHIPPED_LAUNCHER="$REPO/.config/rofi/launcher/style.rasi"
SHIPPED_POWERMENU="$REPO/.config/rofi/powermenu/style.rasi"

# ---- the premise: the shipped file really does promise this ----------------
#
# Every check below is about a promise the file makes. If the wording ever
# changes, these say so rather than testing nothing.
check "the shipped launcher style names images/wallpaper.<ext> in its header" \
  "$(grep -c 'images/wallpaper\.<ext>' "$SHIPPED_LAUNCHER")" "1"
check "and promises everything else is kept" \
  "$(grep -c 'Everything else here is kept' "$SHIPPED_LAUNCHER")" "1"
check "and carries the url() the switch is meant to rewrite" \
  "$(grep -c 'images/wallpaper\.[a-z]*"' "$SHIPPED_LAUNCHER")" "1"
check "and the powermenu one says the same" \
  "$(grep -c 'images/wallpaper\.<ext>' "$SHIPPED_POWERMENU")" "1"

# ---- the pattern the switcher uses, applied the way it applies it ----------
#
# Read out of theme-switcher.sh rather than copied here, so this tests what
# ships. Comments stripped, because the script explains the old pattern in one.
pattern=$(sed 's/#.*//' "$BIN/theme-switcher.sh" |
  grep -oE 's\|images/wallpaper[^|]*\|images/wallpaper[^|]*\|' | head -1)
if [[ -z $pattern ]]; then
  fail "could not read the rewrite pattern out of theme-switcher.sh"
else
  pass "read the rewrite pattern out of theme-switcher.sh"
fi

apply_switch() {
  local file="$1" ext="$2" expr
  expr="${pattern//\$WP_EXT/$ext}"
  sed -i "$expr" "$file"
}

work="$TMP/style.rasi"
cp "$SHIPPED_LAUNCHER" "$work"

apply_switch "$work" jpg
apply_switch "$work" png
apply_switch "$work" jpg

check "after three theme switches the header is untouched" \
  "$(cmp -s <(sed -n '1,3p' "$SHIPPED_LAUNCHER") <(sed -n '1,3p' "$work") && echo same || echo changed)" \
  "same"
check "and the header still reads <ext>, not a real extension" \
  "$(grep -c 'images/wallpaper\.<ext>' "$work")" "1"
check "while the url() was rewritten to the last extension asked for" \
  "$(grep -c 'images/wallpaper\.jpg"' "$work")" "1"
check "and no earlier extension is left behind" \
  "$(grep -c 'images/wallpaper\.png"' "$work")" "0"

# Anti-vacuity: the rewrite has to actually change something, or "the header is
# untouched" would hold for a pattern that matches nothing at all.
png_work="$TMP/style-png.rasi"
cp "$SHIPPED_LAUNCHER" "$png_work"
apply_switch "$png_work" png
check "the rewrite really does change the file, so these checks are not vacuous" \
  "$(cmp -s "$SHIPPED_LAUNCHER" "$png_work" && echo unchanged || echo changed)" "changed"
check "and what it changed is the url() line" \
  "$(grep -c 'images/wallpaper\.png"' "$png_work")" "1"

# Everything outside the header and the url() line survives.
check "and every other line is identical to the shipped file" \
  "$(diff <(grep -vn 'images/wallpaper' "$SHIPPED_LAUNCHER") \
          <(grep -vn 'images/wallpaper' "$png_work") >/dev/null && echo same || echo changed)" \
  "same"

# ---- the migration repairs a file already damaged --------------------------

H="$TMP/home"
mkdir -p "$H/.config/rofi/launcher" "$H/.config/rofi/powermenu"
cp "$SHIPPED_LAUNCHER" "$H/.config/rofi/launcher/style.rasi"
cp "$SHIPPED_POWERMENU" "$H/.config/rofi/powermenu/style.rasi"

# Damaged the way the old pattern damaged it, not by writing the broken text
# here. A fixture that only resembles the damage would prove nothing.
old_pattern='s|images/wallpaper\.[a-z]*|images/wallpaper.jpg|'
for t in launcher powermenu; do
  sed -i "$old_pattern" "$H/.config/rofi/$t/style.rasi"
done
check "the fixture really is damaged before the migration runs" \
  "$(grep -c 'images/wallpaper\.jpg<ext>' "$H/.config/rofi/launcher/style.rasi")" "1"

HOME="$H" bash "$MIGRATION" >"$TMP/out" 2>&1
check "the migration repairs the launcher header" \
  "$(cmp -s <(sed -n '1,3p' "$SHIPPED_LAUNCHER") <(sed -n '1,3p' "$H/.config/rofi/launcher/style.rasi") && echo same || echo changed)" \
  "same"
check "and the powermenu one" \
  "$(cmp -s <(sed -n '1,3p' "$SHIPPED_POWERMENU") <(sed -n '1,3p' "$H/.config/rofi/powermenu/style.rasi") && echo same || echo changed)" \
  "same"
check "and leaves the url() where the theme switch put it" \
  "$(grep -c 'images/wallpaper\.jpg"' "$H/.config/rofi/launcher/style.rasi")" "1"
check "and says how many it touched" \
  "$(grep -c 'in 2 rofi style file' "$TMP/out")" "1"

# Run twice: a migration that repairs on every run would keep reporting work.
HOME="$H" bash "$MIGRATION" >"$TMP/out2" 2>&1
check "running it again finds nothing to do" \
  "$(grep -c 'Nothing to repair' "$TMP/out2")" "1"

# A file someone edited themselves is not touched.
mine="$TMP/mine/.config/rofi/launcher/style.rasi"
mkdir -p "$(dirname "$mine")" "$TMP/mine/.config/rofi/powermenu"
printf '/* my own header */\nbackground-image: url("images/wallpaper.jpg", width);\n' >"$mine"
before=$(cat "$mine")
HOME="$TMP/mine" bash "$MIGRATION" >/dev/null 2>&1
check "a style.rasi with no damaged header is left exactly as it was" \
  "$([[ $(cat "$mine") == "$before" ]] && echo unchanged || echo edited)" "unchanged"

# A home with no rofi config at all must not fail.
mkdir -p "$TMP/bare"
HOME="$TMP/bare" bash "$MIGRATION" >/dev/null 2>&1
check "a home with no rofi style files exits 0" "$?" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
