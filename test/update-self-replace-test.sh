#!/bin/bash
# hyprsimple-update.sh refreshes ~/.local/bin, and one of the scripts it
# refreshes is itself. This suite pins the property that makes that survivable:
# a script is replaced by rename, not rewritten in place, so a running shell
# keeps reading the version it started with.
# Never touches the real ~/.local/bin.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO/.local/bin/hyprsimple-update.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# An inode-preserving write is what corrupts a running script. Asserting on the
# mechanism rather than on a message keeps this readable when the wording of
# the loop changes.

refresh_block=$(sed -n '/Refreshing helper scripts/,/^done$/p' "$UPDATE")
check "the refresh loop renames into place" \
  "$(grep -c 'mv -f' <<<"$refresh_block")" "1"
check "the refresh loop does not cp directly over the target" \
  "$(grep -cE '^\s*cp -f "\$script" "\$target"\s*$' <<<"$refresh_block")" "0"

# The property under test is bash's, not hyprsimple's, so the check runs it
# rather than trusting either. The replacement is deliberately longer than the
# original, because an equal-length one cannot shift the read offset and so
# cannot fail.

mkdir -p "$TMP/bin"
cat >"$TMP/new.sh" <<'NEW'
# a longer header, so every byte offset below it shifts
# padding padding padding padding padding padding padding
# padding padding padding padding padding padding padding
echo "REPLACEMENT"
NEW

# in place, the way cp -f behaves: the tail of the running script is corrupted
cat >"$TMP/bin/inplace.sh" <<'INPLACE'
cp -f "$TMP_DIR/new.sh" "$0"
echo "TAIL-REACHED"
INPLACE
inplace_out=$(TMP_DIR="$TMP" bash "$TMP/bin/inplace.sh" 2>&1)
check "an in-place rewrite corrupts the running script" \
  "$(grep -c 'TAIL-REACHED' <<<"$inplace_out")" "0"

# by rename, the way the fix behaves: the running script finishes intact
cat >"$TMP/bin/rename.sh" <<'RENAME'
cp -f "$TMP_DIR/new.sh" "$0.new" && mv -f "$0.new" "$0"
echo "TAIL-REACHED"
RENAME
rename_out=$(TMP_DIR="$TMP" bash "$TMP/bin/rename.sh" 2>&1)
check "a rename lets the running script finish" \
  "$(grep -c 'TAIL-REACHED' <<<"$rename_out")" "1"
check "and the new version is what landed on disk" \
  "$(grep -c 'REPLACEMENT' "$TMP/bin/rename.sh")" "1"

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
