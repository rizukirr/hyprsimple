#!/bin/bash
# Every shipped theme named an icon theme that nothing installed.
#
# theme-switcher.sh runs
#
#   gsettings set org.gnome.desktop.interface icon-theme "$(cat icons.theme)"
#
# for every theme, and all sixteen name one: fifteen a Yaru variant, one
# Papirus-Dark. Neither yaru-icon-theme nor papirus-icon-theme was in
# packages.txt or aur-packages.txt. Measured on a live install with rosepine
# active: gsettings read 'Yaru-blue' and /usr/share/icons held only Adwaita,
# breeze and hicolor. GTK silently fell back, so the per-theme icons have never
# worked anywhere.
#
# This is the shape the btop theme had in #86: the whole chain built, and the
# last link never connected. There the config key was never set; here the
# package was never installed.
#
# The dunst drop-in named things that were not installed too, and two settings
# dunst rejects outright. Where dunst is present this suite asks it rather than
# judging its syntax here.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DROPIN="$REPO/default/dunst/10-hyprsimple.conf"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# The variants Yaru actually ships, recorded here rather than fetched: a suite
# must not need the network, and this is the list that made Yaru-gray a bug.
YARU_VARIANTS=(
  Yaru Yaru-bark Yaru-blue Yaru-dark Yaru-magenta Yaru-mate Yaru-olive
  Yaru-prussiangreen Yaru-purple Yaru-red Yaru-sage Yaru-viridian
  Yaru-wartybrown Yaru-yellow
)

# --- every named icon theme comes from a package we install ------------------

themes=0; named=0; unpackaged=(); unknown=()
for t in "$REPO/.config/hypr/themes"/*/; do
  name=$(basename "$t"); [[ $name == templates* ]] && continue
  themes=$((themes + 1))
  icon=$(cat "$t/icons.theme" 2>/dev/null || cat "$t/icon-theme" 2>/dev/null)
  icon=${icon//[$'\n\r']/}
  [[ -z $icon ]] && continue
  named=$((named + 1))
  case "$icon" in
    Yaru*)
      grep -qx 'yaru-icon-theme' "$REPO/aur-packages.txt" || unpackaged+=("$name:$icon")
      printf '%s\n' "${YARU_VARIANTS[@]}" | grep -qx "$icon" || unknown+=("$name:$icon")
      ;;
    Papirus*)
      grep -qx 'papirus-icon-theme' "$REPO/packages.txt" || unpackaged+=("$name:$icon")
      ;;
    *) unknown+=("$name:$icon") ;;
  esac
done

if (( themes < 5 )); then
  fail "found $themes themes, too few for this to mean anything"
else
  pass "checked $themes shipped themes"
fi
check "most of them name an icon theme, so there is something to install" \
  "$([[ $named -ge 10 ]] && echo enough || echo "only $named")" "enough"

u=""; (( ${#unpackaged[@]} > 0 )) && u="$(printf '%s; ' "${unpackaged[@]}")"
check "every named icon theme comes from a package in a list" "$u" ""

# Yaru has no gray. vantablack asked for Yaru-gray, which would have fallen
# back even once the package was installed.
k=""; (( ${#unknown[@]} > 0 )) && k="$(printf '%s; ' "${unknown[@]}")"
check "and every Yaru variant named is one Yaru actually ships" "$k" ""

# The package list entries have to be in the right file: yaru-icon-theme is AUR
# only, papirus-icon-theme is in extra.
check "yaru-icon-theme is in the AUR list, where an AUR-only package belongs" \
  "$(grep -cx 'yaru-icon-theme' "$REPO/aur-packages.txt")" "1"
check "and not in the pacman list, which cannot resolve it" \
  "$(grep -cx 'yaru-icon-theme' "$REPO/packages.txt")" "0"
check "papirus-icon-theme is in the pacman list, being in extra" \
  "$(grep -cx 'papirus-icon-theme' "$REPO/packages.txt")" "1"

# --- the dunst drop-in -------------------------------------------------------

check "the drop-in no longer hardcodes Papirus icon paths" \
  "$(grep -c 'icon_path' "$DROPIN")" "0"
check "and names icon themes with a fallback instead" \
  "$(grep -c 'icon_theme = "Papirus-Dark, Adwaita"' "$DROPIN")" "1"
check "its dmenu uses rofi, which hyprsimple installs" \
  "$(grep -c 'dmenu = /usr/bin/rofi -dmenu' "$DROPIN")" "1"
# Comments stripped: the note left beside the dmenu line names wofi, and an
# unanchored grep counts that.
code_of() { sed 's/#.*//' "$1"; }
check "and not wofi, which is in neither list" \
  "$(code_of "$DROPIN" | grep -c 'wofi')" "0"
check "stripping comments leaves the drop-in's settings intact" \
  "$(code_of "$DROPIN" | grep -c 'dmenu = /usr/bin/rofi')" "1"
# grep -c across two files prints one count per file. Summed in the shell,
# because bc is not installed on a hyprsimple machine.
wofi_listed=0
while read -r n; do wofi_listed=$((wofi_listed + n)); done < <(
  grep -cx 'wofi' "$REPO/packages.txt" "$REPO/aur-packages.txt" | cut -d: -f2
)
check "wofi really is absent from both lists, which is why" "$wofi_listed" "0"

if ! command -v dunst >/dev/null 2>&1; then
  pass "dunst is not installed here, so its verdict is skipped"
else
  # A theme directory dunst can find, so the only remaining warning on a
  # machine without papirus-icon-theme installed does not mask a real one.
  mkdir -p "$TMP/icons/Papirus-Dark/16x16/status"
  printf '[Icon Theme]\nName=Papirus-Dark\nDirectories=16x16/status\n[16x16/status]\nSize=16\n' \
    >"$TMP/icons/Papirus-Dark/index.theme"
  complaints=$(XDG_DATA_DIRS="$TMP:/usr/share" dunst --config "$DROPIN" --print 2>&1 |
    grep -icE 'warning|legacy|does.t exist' || true)
  check "dunst accepts the drop-in with no warning of any kind" "$complaints" "0"

  # And the two it used to make are gone for the right reason, not because the
  # check stopped looking.
  probe() {
    printf '[global]\n%s\n' "$1" >"$TMP/probe.conf"
    dunst --config "$TMP/probe.conf" --print 2>&1 | grep -icE 'warning|legacy|does.t exist' || true
  }
  check "dunst still rejects the old offset syntax, so that check means something" \
    "$(probe 'offset = 10x10')" "1"
  check "and still rejects notification_height" \
    "$(probe 'notification_height = 0')" "1"
fi

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
