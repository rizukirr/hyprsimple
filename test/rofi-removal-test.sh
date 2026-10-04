#!/bin/bash
# Checks that rofi is gone from what hyprsimple ships, and that the migration
# clears it from a machine that already has it without touching what is the
# user's.
#
# Nothing here removes a package or touches the real ~/.config. pacman and sudo
# are stand-ins that record what they were asked, and every home is a directory
# of this suite's own.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

BASH_BIN="$(command -v bash)"

# ---- nothing shipped starts or installs rofi ----------------------------------

check "rofi is in neither package list" \
  "$(cat "$REPO/packages.txt" "$REPO/aur-packages.txt" | grep -cx 'rofi')" "0"
check "no rofi config is shipped" \
  "$([[ -e $REPO/.config/rofi || -e $REPO/default/rofi ]] && echo shipped || echo none)" "none"
check "nor a rofi colour template" \
  "$(find "$REPO/.config/hypr/themes/templates" -name '*rofi*' | wc -l | tr -d ' ')" "0"

# Comments stripped, since several scripts say what they did before. What is
# looked for is the word itself: "profile" holds the same four letters.
callers=()
while IFS= read -r f; do
  sed 's/^[[:space:]]*#.*//; s/^[[:space:]]*--.*//' "$f" |
    grep -qE '(^|[^a-zA-Z_-])rofi([^a-zA-Z_-]|$)' && callers+=("${f#"$REPO"/}")
done < <(find "$REPO/.local/bin" "$REPO/default" "$REPO/.config" "$REPO/install.sh" \
  -type f \( -name '*.sh' -o -name '*.lua' -o -name '*.conf' -o -name '*.qml' \))
check "no shipped script or config names rofi in its code" "${callers[*]:-}" ""

for gone in hyprsimple-image-picker.sh hyprsimple-menu-exclusive.sh; do
  check "$gone is no longer shipped" \
    "$([[ -e $REPO/.local/bin/$gone ]] && echo shipped || echo gone)" "gone"
done
check "and nothing shipped calls either" \
  "$(grep -rlE 'hyprsimple-(image-picker|menu-exclusive)\.sh' "$REPO/.local/bin" "$REPO/default" "$REPO/.config" "$REPO/install.sh" | wc -l | tr -d ' ')" "0"

# ---- the migration --------------------------------------------------------------

MIGRATION="$(grep -l 'Remove rofi, now that every menu is a panel' "$REPO"/migrations/*.sh | head -1)"
check "the migration was found" "$([[ -n $MIGRATION ]] && echo found || echo missing)" "found"

STUB="$TMP/stub"; mkdir -p "$STUB"
for tool in grep rm cat; do ln -sf "$(command -v "$tool")" "$STUB/$tool"; done
# pacman -Qi answers from $ROFI_INSTALLED. sudo records the removal it was asked
# for and answers from $REMOVAL_WORKS.
cat >"$STUB/pacman" <<'STUBEOF'
#!/bin/bash
[[ $1 == -Qi && ${ROFI_INSTALLED:-} == yes ]]
STUBEOF
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_LOG"
[[ ${REMOVAL_WORKS:-yes} == yes ]]
STUBEOF
chmod +x "$STUB/pacman" "$STUB/sudo"
check "the real pacman is unreachable from here" "$(PATH="$STUB" command -v pacman)" "$STUB/pacman"
check "and so is the real sudo" "$(PATH="$STUB" command -v sudo)" "$STUB/sudo"

# An install as it stands before this update: the two links into the install,
# the user's own rofi files, and the scripts left in ~/.local/bin.
old_home() {
  local h="$TMP/home-$1"
  mkdir -p "$h/.config/rofi/launcher" "$h/.config/hypr/bindings" "$h/.local/bin"
  ln -s "$TMP/install/default/rofi" "$h/.config/rofi/hyprsimple"
  ln -s "$TMP/install/generated/rofi-colors.rasi" "$h/.config/rofi/rofi-colors.rasi"
  printf '/* mine */\n' >"$h/.config/rofi/config.rasi"
  printf '/* mine */\n' >"$h/.config/rofi/launcher/style.rasi"
  for s in hyprsimple-image-picker.sh hyprsimple-menu-exclusive.sh screenshot.sh; do
    printf '#!/bin/bash\n' >"$h/.local/bin/$s"
  done
  printf 'hl.bind("SUPER + T", hl.dsp.exec_cmd(vars.terminal), { description = "Terminal" })\n' \
    >"$h/.config/hypr/bindings/applications.lua"
  # A file that holds the letters without naming the program.
  printf 'profile {\n  time = 7:30\n}\n' >"$h/.config/hypr/hyprsunset.conf"
  printf '%s' "$h"
}
migrate() {
  : >"$TMP/sudo-log"
  HOME="$1" SUDO_LOG="$TMP/sudo-log" PATH="$STUB" "$BASH_BIN" "$MIGRATION" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}
exists() { [[ -e $1 || -L $1 ]] && echo present || echo gone; }

h=$(old_home plain)
ROFI_INSTALLED=yes migrate "$h"
check "the link to the install's rofi defaults is removed" "$(exists "$h/.config/rofi/hyprsimple")" "gone"
check "and the link to the theme's rofi colours" "$(exists "$h/.config/rofi/rofi-colors.rasi")" "gone"
check "the user's own rofi config is left" "$(cat "$h/.config/rofi/config.rasi")" "/* mine */"
check "and their launcher style" "$(cat "$h/.config/rofi/launcher/style.rasi")" "/* mine */"
check "the image picker script is removed" "$(exists "$h/.local/bin/hyprsimple-image-picker.sh")" "gone"
check "and the helper that closed an open rofi menu" "$(exists "$h/.local/bin/hyprsimple-menu-exclusive.sh")" "gone"
check "a script that still ships is left" "$(exists "$h/.local/bin/screenshot.sh")" "present"
check "the rofi package is removed" "$(cat "$TMP/sudo-log")" "pacman -Rs --noconfirm rofi"
check "and it says so" "$(grep -c 'Removed the rofi package' "$TMP/out")" "1"
check "a file that only holds the letters, in profile, does not count as calling rofi" \
  "$(grep -c 'still call rofi' "$TMP/out")" "0"
check "and it succeeds" "$(cat "$TMP/rc")" "0"

ROFI_INSTALLED="" migrate "$h"
check "run again with rofi gone, it never reaches sudo" "$(wc -c <"$TMP/sudo-log" | tr -d ' ')" "0"
check "and succeeds" "$(cat "$TMP/rc")" "0"

h=$(old_home refused)
ROFI_INSTALLED=yes REMOVAL_WORKS=no migrate "$h"
check "a removal pacman refuses does not fail the update" "$(cat "$TMP/rc")" "0"
check "and the command to run by hand is printed" "$(grep -c 'sudo pacman -Rs rofi' "$TMP/out")" "1"

# A binding of the user's own that starts rofi.
h=$(old_home own-rofi)
printf 'hl.bind("SUPER + R", hl.dsp.exec_cmd("rofi -show run"), { description = "Run" })\n' \
  >>"$h/.config/hypr/bindings/applications.lua"
before=$(cat "$h/.config/hypr/bindings/applications.lua")
ROFI_INSTALLED=yes migrate "$h"
check "with a binding of your own that starts rofi, the package is left installed" \
  "$(wc -c <"$TMP/sudo-log" | tr -d ' ')" "0"
check "the file is named" "$(grep -c 'bindings/applications.lua' "$TMP/out")" "1"
check "and is not rewritten" "$(cat "$h/.config/hypr/bindings/applications.lua")" "$before"
check "the helper is left too, since such a binding may go through it" \
  "$(exists "$h/.local/bin/hyprsimple-menu-exclusive.sh")" "present"
check "the dangling links are still removed" "$(exists "$h/.config/rofi/hyprsimple")" "gone"
check "and it succeeds" "$(cat "$TMP/rc")" "0"

# A binding that goes through the helper.
h=$(old_home own-helper)
printf 'hl.bind("SUPER + R", hl.dsp.exec_cmd(home .. "/.local/bin/hyprsimple-menu-exclusive.sh my-menu"), {})\n' \
  >>"$h/.config/hypr/bindings/applications.lua"
ROFI_INSTALLED=yes migrate "$h"
check "a binding of your own that calls the helper keeps the helper" \
  "$(exists "$h/.local/bin/hyprsimple-menu-exclusive.sh")" "present"
check "and the package" "$(wc -c <"$TMP/sudo-log" | tr -d ' ')" "0"

# A home with nothing of rofi's in it.
mkdir -p "$TMP/home-bare"
ROFI_INSTALLED="" migrate "$TMP/home-bare"
check "a home with nothing to clear exits 0" "$(cat "$TMP/rc")" "0"
check "and creates nothing" "$(find "$TMP/home-bare" -mindepth 1 | wc -l | tr -d ' ')" "0"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
