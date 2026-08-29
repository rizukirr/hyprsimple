#!/bin/bash
# Checks the checksum gate in the config split migration.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1787992467.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# An untouched file, byte-identical to what shipped, must be replaced.
home="$TMP/untouched"
mkdir -p "$home/.config/hypr/bindings"
cp "$REPO/.config/hypr/monitors.lua" "$home/.config/hypr/monitors.lua"
printf 'edited by the user\n' >"$home/.config/hypr/windows.lua"
before_edited=$(md5sum "$home/.config/hypr/windows.lua" | cut -d' ' -f1)

HOME="$home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/out1" 2>&1
check "migration exits 0" "$?" "0"

saved=$(find "$home/.config/hypr" -name 'windows.lua.pre-split.*' | head -1)
check "an edited file is saved aside" "$([[ -n $saved ]] && echo yes || echo no)" yes
check "the saved copy keeps the original content"   "$([[ -n $saved ]] && md5sum "$saved" | cut -d' ' -f1)" "$before_edited"
check "the live file is no longer the edited one"   "$([[ $(md5sum "$home/.config/hypr/windows.lua" | cut -d' ' -f1) != "$before_edited" ]] && echo yes || echo no)" yes

if grep -q "windows.lua" "$TMP/out1"; then pass "an edited file is named in the output"
else printf 'not ok - an edited file is named in the output\n' >&2; failures=$((failures + 1)); fi

# Running again must change nothing.
snapshot_before=$(find "$home" -type f -exec md5sum {} + | sort)
HOME="$home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >/dev/null 2>&1
snapshot_after=$(find "$home" -type f -exec md5sum {} + | sort)
check "migration is idempotent" "$snapshot_after" "$snapshot_before"

# A missing config directory is a no-op rather than an error.
HOME="$TMP/nothing" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >/dev/null 2>&1
check "absent config directory is a no-op" "$?" "0"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
