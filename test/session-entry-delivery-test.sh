#!/bin/bash
# Checks that hyprsimple-update.sh delivers hyprsimple-session.sh to an
# existing install, with no migration involved.
#
# Everything happens against a throwaway file:// origin under a temp directory,
# the way update-channel-test.sh does it. HOME and HYPRSIMPLE_PATH are
# redirected, so the real install and the real ~/.local/bin are never read or
# written, and pgrep and hyprctl are stubs so no compositor is reloaded.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO/.local/bin/hyprsimple-update.sh"
SCRIPT="$REPO/.local/bin/hyprsimple-session.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# The update ends by reloading Hyprland and running the migration runner.
# Neither belongs here. pgrep unstubbed would find the real compositor.
STUB="$TMP/stub"
mkdir -p "$STUB"
printf '#!/bin/bash\nexit 1\n' >"$STUB/pgrep"
printf '#!/bin/bash\nexit 0\n' >"$STUB/hyprctl"
chmod +x "$STUB/pgrep" "$STUB/hyprctl"

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.local/bin"
MIGRATE_LOG="$TMP/migrate.log"
printf '#!/bin/bash\nprintf "ran\\n" >>"%s"\nexit 0\n' "$MIGRATE_LOG" >"$FAKE_HOME/.local/bin/hyprsimple-migrate.sh"
chmod +x "$FAKE_HOME/.local/bin/hyprsimple-migrate.sh"

ORIGIN="$TMP/origin.git"
WORK="$TMP/work"
INSTALL="$TMP/install"

git init -q --bare "$ORIGIN"
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
git clone -q "$ORIGIN" "$WORK" 2>/dev/null
git -C "$WORK" config user.email test@example.com
git -C "$WORK" config user.name test

# The install as it is before this change ships: a release with no
# hyprsimple-session.sh in it.
printf '0.4.5\n' >"$WORK/version"
git -C "$WORK" add version
git -C "$WORK" commit -qm "version 0.4.5"
git -C "$WORK" push -q origin main

git clone -q --depth 1 "file://$ORIGIN" "$INSTALL"
[[ -e $INSTALL/.git ]] || { printf 'not ok - fixture clone produced nothing\n' >&2; exit 1; }
check "the install starts without the script" \
  "$([[ -e $INSTALL/.local/bin/hyprsimple-session.sh ]] && echo yes || echo no)" "no"
check "and the fake home has none either" \
  "$([[ -e $FAKE_HOME/.local/bin/hyprsimple-session.sh ]] && echo yes || echo no)" "no"

# The change lands on main: the script, and nothing under migrations/.
mkdir -p "$WORK/.local/bin"
cp "$SCRIPT" "$WORK/.local/bin/hyprsimple-session.sh"
printf '0.4.6\n' >"$WORK/version"
git -C "$WORK" add -A
git -C "$WORK" commit -qm "Add hyprsimple-session.sh"
git -C "$WORK" push -q origin main

HOME="$FAKE_HOME" HYPRSIMPLE_PATH="$INSTALL" PATH="$STUB:$PATH" \
  bash "$UPDATE" >"$TMP/out" 2>&1
status=$?
check "the update exits 0" "$status" "0"
check "the install moved to the new commit" "$(cat "$INSTALL/version")" "0.4.6"
check "the script is now in the fake ~/.local/bin" \
  "$([[ -f $FAKE_HOME/.local/bin/hyprsimple-session.sh ]] && echo yes || echo no)" "yes"
check "and it is executable" \
  "$([[ -x $FAKE_HOME/.local/bin/hyprsimple-session.sh ]] && echo yes || echo no)" "yes"
check "and byte-identical to the shipped one" \
  "$(cmp -s "$SCRIPT" "$FAKE_HOME/.local/bin/hyprsimple-session.sh" && echo same || echo differs)" "same"
check "the migration runner was called, as on every update" \
  "$([[ -f $MIGRATE_LOG ]] && echo yes || echo no)" "yes"
check "and this repository ships no migration for the session entry" \
  "$(grep -rl 'hyprsimple-session' "$REPO/migrations" 2>/dev/null | wc -l)" "0"

# The delivered copy works from where it landed.
SESSIONS="$TMP/wayland-sessions"
HYPRSIMPLE_SESSION_DIR="$SESSIONS" "$FAKE_HOME/.local/bin/hyprsimple-session.sh" >/dev/null 2>&1; status=$?
check "the delivered script adds the entry" "$status" "0"
check "at the overridden path" \
  "$([[ -f $SESSIONS/hyprsimple.desktop ]] && echo yes || echo no)" "yes"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
