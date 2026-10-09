#!/bin/bash
# Compatibility removal, DNS error handling and yazi cleanup regressions.

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

check "obsolete helper is absent" "$(test -e "$BIN/hyprsimple-muslimtify.sh" && echo present || echo absent)" "absent"
for shell in bashrc.sh zsh.sh fish.fish; do
  check "$shell has no compatibility aliases" "$(grep -cE 'muslimtify-(add|remove)' "$BIN/$shell")" "0"
done

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

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
