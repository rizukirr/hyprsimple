#!/bin/bash
# Defects in scripts that had never been run by anything. The muslimtify one is
# the worst: with the package absent, remove took the uninstall branch, tried
# to remove a package with no name, and died before finishing.

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
# A qs of its own. This suite names the script that restarts the bar, which can
# also ask the running bar to hide, and the real one would act on the bar of
# whoever is running the tests.
printf '#!/bin/bash\nexit 0\n' >"$STUB/qs"; chmod +x "$STUB/qs"

# installed_pkgs is lifted rather than the script run, because running it
# invokes an AUR helper and restarts the bar.
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
# the uninstall branch, or remove dies before restarting the bar.
printf '#!/bin/bash\nexit 1\n' >"$STUB/pacman"; chmod +x "$STUB/pacman"
mapfile -t pkgs < <(PATH="$STUB:$PATH" installed_pkgs)
if (( ${#pkgs[@]} > 0 )); then branch=uninstall; else branch=skip; fi
check "with nothing installed, remove skips the uninstall branch" "$branch" "skip"

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

# --- the bar is restarted, and nothing edits a bar config ------------------
#
# The script used to patch a module into waybar's config and stylesheet. The
# bar now shows prayer times on its own, so add and remove only have to restart
# it, because it looks for muslimtify once at startup.
code="$(sed 's/#.*//' "$BIN/hyprsimple-muslimtify.sh")"
check "add and remove both restart the bar" \
  "$(grep -c '^  reload_bar$' <<<"$code")" "2"
check "through the shared restart script" \
  "$(grep -c 'hyprsimple-restart-bar.sh" --if-running' <<<"$code")" "1"
check "and no bar config is edited" \
  "$(grep -ciE 'waybar|sed -i' <<<"$code")" "0"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
