#!/bin/bash
# Four defects in scripts that had never been run by anything. The muslimtify
# one is the worst: with the package absent, remove took the uninstall branch,
# tried to remove a package with no name, and died before cleaning the waybar
# config it exists to clean.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"; mkdir -p "$STUB"

# installed_pkgs is lifted rather than the script run, because running it
# invokes an AUR helper and edits waybar's config.
sed -n '/^installed_pkgs()/,/^}/p' "$BIN/hyprsimple-muslimtify.sh" >"$TMP/pkgs.sh"
check "installed_pkgs was lifted out" "$(grep -c '^installed_pkgs()' "$TMP/pkgs.sh")" "1"
# shellcheck disable=SC1091
. "$TMP/pkgs.sh"

printf '#!/bin/bash\nexit 1\n' >"$STUB/pacman"; chmod +x "$STUB/pacman"
mapfile -t pkgs < <(PATH="$STUB:$PATH" installed_pkgs)
check "nothing installed yields an empty package list" "${#pkgs[@]}" "0"

printf '#!/bin/bash\n[[ $2 == muslimtify ]] && exit 0\nexit 1\n' >"$STUB/pacman"; chmod +x "$STUB/pacman"
mapfile -t pkgs < <(PATH="$STUB:$PATH" installed_pkgs)
check "one installed package yields one entry" "${#pkgs[@]}" "1"
check "and it is the right one" "${pkgs[0]}" "muslimtify"

# The consequence, stated as the caller sees it. An empty list must not take
# the uninstall branch, or remove dies before cleaning waybar.
printf '#!/bin/bash\nexit 1\n' >"$STUB/pacman"; chmod +x "$STUB/pacman"
mapfile -t pkgs < <(PATH="$STUB:$PATH" installed_pkgs)
if (( ${#pkgs[@]} > 0 )); then branch=uninstall; else branch=skip; fi
check "with nothing installed, remove skips the uninstall branch" "$branch" "skip"

# backup kept the most recent copy, so add then remove destroyed the original.
sed -n '/^backup()/,/^}/p' "$BIN/hyprsimple-muslimtify.sh" >"$TMP/backup.sh"
# shellcheck disable=SC1091
. "$TMP/backup.sh"
f="$TMP/config.jsonc"
printf 'ORIGINAL\n' >"$f"
backup "$f"; printf 'PATCHED BY ADD\n' >"$f"
backup "$f"; printf 'CLEANED BY REMOVE\n' >"$f"
check "the backup still holds the file as it was before hyprsimple touched it" \
  "$(cat "$f.bak")" "ORIGINAL"

# setup-dns.sh announced success whatever systemctl did, on a machine whose
# DNS was then broken.
check "setup-dns checks that systemd-resolved is running" \
  "$(grep -c 'systemctl is-active --quiet systemd-resolved' "$BIN/setup-dns.sh")" "1"
check "every systemd-resolved restart is checked" \
  "$(grep -c 'systemctl restart systemd-resolved ||' "$BIN/setup-dns.sh")" "2"
check "no restart is left unchecked" \
  "$(grep -cE 'systemctl restart systemd-resolved$' "$BIN/setup-dns.sh")" "0"

# The yazi wrapper skipped its own cleanup on every exit that did not change
# directory, leaving a temp file behind each time.
sed -n '/^y() {/,/^}/p' "$BIN/bashrc.sh" >"$TMP/y.sh"
check "the yazi wrapper was lifted out" "$(grep -c '^y() {' "$TMP/y.sh")" "1"
printf '#!/bin/bash\nfor a in "$@"; do case $a in --cwd-file=*) printf "%%s" "$PWD" > "${a#--cwd-file=}";; esac; done\n' >"$STUB/yazi"
chmod +x "$STUB/yazi"
# shellcheck disable=SC1091
. "$TMP/y.sh"
before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'yazi-cwd.*' 2>/dev/null | wc -l)
PATH="$STUB:$PATH" y >/dev/null 2>&1
after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'yazi-cwd.*' 2>/dev/null | wc -l)
check "exiting yazi without changing directory leaves no temp file" "$after" "$before"

# And a cd that fails must still clean up, while reporting the failure. The
# first fix for the leak dropped the failure signal entirely, which shellcheck
# caught as SC2164 before it was pushed.
printf '#!/bin/bash\nfor a in "$@"; do case $a in --cwd-file=*) printf "%%s" "/nonexistent-xyz" > "${a#--cwd-file=}";; esac; done\n' >"$STUB/yazi"
chmod +x "$STUB/yazi"
before=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'yazi-cwd.*' 2>/dev/null | wc -l)
PATH="$STUB:$PATH" y >/dev/null 2>&1
check "a failed cd is reported" "$?" "1"
after=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'yazi-cwd.*' 2>/dev/null | wc -l)
check "a failed cd still cleans up its temp file" "$after" "$before"

# --- the module goes into modules-left, and only there -----------------------
#
# The two substitutions matched "hyprland/workspaces" wherever it appeared, so a
# config with workspaces in two lists got the module in both and the prayer
# times showed up twice in the bar:
#
#   "modules-left":  ["hyprland/workspaces", "custom/muslimtify", "clock"]
#   "modules-right": ["hyprland/workspaces", "custom/muslimtify", "tray"]
#
# The comment above them has always said modules-left. Only the address makes
# it true.
#
# The substitutions are read out of the script rather than copied here, so this
# exercises what ships.
# Only the ones between the injection comment and the module definition that
# follows it. Taking every substitution mentioning custom/muslimtify also took
# the two that remove it, which stripped the module straight back out and made
# five checks fail for a reason that had nothing to do with the fix.
mapfile -t inject_seds < <(
  sed -n '/Insert into modules-left/,/Insert module definition/p' \
    "$BIN/hyprsimple-muslimtify.sh" |
    grep -oE "sed -i '[^']*'" |
    sed "s/^sed -i '//; s/'$//"
)
if (( ${#inject_seds[@]} != 3 )); then
  fail "read ${#inject_seds[@]} injection substitutions out of the script, and there are three"
else
  pass "read the three injection substitutions out of the script"
fi

apply_injection() {
  local file="$1" expr
  for expr in "${inject_seds[@]}"; do
    sed -i "$expr" "$file"
  done
}

two_lists="$TMP/waybar-two-lists.jsonc"
cat >"$two_lists" <<'JSONEOF'
{
    "modules-left": ["hyprland/workspaces", "clock"],
    "modules-center": ["hyprland/window"],
    "modules-right": ["hyprland/workspaces", "tray"],
    "custom/power": { "format": "x" }
}
JSONEOF
apply_injection "$two_lists"

check "with workspaces in two lists, modules-left gets the module" \
  "$(grep -c '"modules-left".*custom/muslimtify' "$two_lists")" "1"
check "and modules-right does not" \
  "$(grep -c '"modules-right".*custom/muslimtify' "$two_lists")" "0"
check "so the module appears exactly once" \
  "$(grep -c 'custom/muslimtify' "$two_lists")" "1"

# Anti-vacuity: the injection still does something on an ordinary config, and
# on the shape where modules-left holds nothing but workspaces.
ordinary="$TMP/waybar-ordinary.jsonc"
cat >"$ordinary" <<'JSONEOF'
{
    "modules-left": ["hyprland/workspaces", "clock"],
    "modules-right": ["tray"]
}
JSONEOF
apply_injection "$ordinary"
check "an ordinary config still gets the module" \
  "$(grep -c '"modules-left".*custom/muslimtify' "$ordinary")" "1"

solo="$TMP/waybar-solo.jsonc"
printf '{\n    "modules-left": ["hyprland/workspaces"],\n    "modules-right": ["clock"]\n}\n' >"$solo"
apply_injection "$solo"
check "and so does one whose modules-left holds only workspaces" \
  "$(grep -c '"modules-left".*custom/muslimtify' "$solo")" "1"
check "without doubling it, which the dedupe is there for" \
  "$(grep -c 'custom/muslimtify' "$solo")" "1"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
