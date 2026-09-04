#!/bin/bash
# bootstrap.sh and install.sh both put the canonical install where it belongs,
# and both used to do it in this order:
#
#   rm -rf "$HYPRSIMPLE_PATH"      <- the existing install, gone
#   mkdir -p "$HYPRSIMPLE_PATH"
#   ... ask whether to continue    <- answering "no" returns here
#
# So declining at the prompt deleted the install and then declined to replace
# it. Nothing to undo and nothing left. Worse, the empty directory left behind
# failed the "does this look like a hyprsimple checkout" guard on every later
# run, so the user was told to move aside a directory the script had made.
#
# test/install-copy-test.sh eval's copy_source_to_canonical_path out of
# bootstrap.sh and exercises it alone, which is why this was invisible: the bug
# was never in the function, it was in the order of the script around it. This
# suite runs bootstrap.sh as a script.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'not ok - refusing to operate outside the fixture: %s\n' "${1:-<empty>}" >&2
    exit 1
  fi
}

# The prompt is guarded on `[[ -t 0 ]]`, so reaching it at all needs a
# terminal. Asserted rather than skipped: a skip that fires everywhere is a
# check that never runs.
if command -v script >/dev/null 2>&1; then
  pass "script(1) is available, so the prompt can be reached"
else
  fail "script(1) is missing, so none of the prompt checks below can run"
  exit 1
fi

# ---- a source checkout with uncommitted changes --------------------------

SRC="$TMP/src"
must_be_fixture "$SRC"
mkdir -p "$SRC/migrations" "$SRC/.local/bin"
cp "$REPO/bootstrap.sh" "$SRC/bootstrap.sh"
printf '#!/bin/bash\necho install\n' >"$SRC/install.sh"
printf 'echo migration\n' >"$SRC/migrations/1.sh"
printf '#!/bin/bash\nexit 0\n' >"$SRC/.local/bin/hyprsimple-migrate.sh"
git -C "$SRC" init -q .
git -C "$SRC" config user.email t@example.com
git -C "$SRC" config user.name t
git -C "$SRC" add -A >/dev/null
git -C "$SRC" commit -qm init
printf 'uncommitted\n' >>"$SRC/install.sh"

DEST="$TMP/dest"

# The migrate step runs against the real home otherwise, and this suite must
# never touch it. HOME is redirected for every run below.
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.local/bin"

run_bootstrap() {
  local answer="$1"
  must_be_fixture "$DEST"
  printf '%s\n' "$answer" |
    script -qec "env HOME=$FAKE_HOME HYPRSIMPLE_PATH=$DEST bash $SRC/bootstrap.sh" /dev/null 2>&1
}

seed_existing_install() {
  must_be_fixture "$DEST"
  rm -rf "$DEST"
  mkdir -p "$DEST"
  printf '#!/bin/bash\necho OLD\n' >"$DEST/install.sh"
  printf 'irreplaceable\n' >"$DEST/USER_DATA.txt"
}

# ---- declining must not destroy the existing install ---------------------

seed_existing_install
out="$(run_bootstrap n)"
check "declining leaves the existing install in place" \
  "$([[ -f $DEST/USER_DATA.txt ]] && echo kept || echo DESTROYED)" "kept"
check "declining says so" \
  "$(printf '%s' "$out" | grep -c 'Aborted')" "1"
check "declining does not empty the directory" \
  "$(find "$DEST" -mindepth 1 | wc -l)" "2"

# ---- accepting still replaces it -----------------------------------------

seed_existing_install
run_bootstrap y >/dev/null
check "accepting replaces the install" \
  "$([[ -f $DEST/USER_DATA.txt ]] && echo stale || echo replaced)" "replaced"
check "and the committed content is what landed, not the uncommitted edit" \
  "$(grep -c 'uncommitted' "$DEST/install.sh" 2>/dev/null)" "0"

# ---- an empty destination must not wedge the run -------------------------
#
# This is the state the old code left behind, and it made every later run fail
# with a message about moving aside a directory bootstrap itself had created.

must_be_fixture "$DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
out="$(run_bootstrap y)"
check "an empty destination directory is not mistaken for someone else's data" \
  "$(printf '%s' "$out" | grep -c 'does not look like a hyprsimple checkout')" "0"
check "and the install lands in it" \
  "$([[ -f $DEST/install.sh ]] && echo installed || echo missing)" "installed"

# ---- a destination with unrelated content is still refused ---------------

must_be_fixture "$DEST"
rm -rf "$DEST"
mkdir -p "$DEST"
printf 'not hyprsimple\n' >"$DEST/somebody-elses-project.txt"
out="$(run_bootstrap y)"
check "a non-empty directory that is not a checkout is still refused" \
  "$(printf '%s' "$out" | grep -c 'does not look like a hyprsimple checkout')" "1"
check "and its contents are untouched" \
  "$([[ -f $DEST/somebody-elses-project.txt ]] && echo kept || echo DESTROYED)" "kept"

# ---- install.sh has the same shape and needs the same guarantee ----------
#
# Its function is driven directly rather than running the whole installer,
# which would try to install an entire desktop.

DRIVER="$TMP/driver.sh"
{
  printf 'set -eEo pipefail\n'
  printf "RED=''\nYELLOW=''\nNC=''\n"
  printf 'DOTFILES_DIR="%s"\n' "$SRC"
  printf 'HYPRSIMPLE_PATH="%s"\n' "$DEST"
  sed -n '/^dir_is_empty() {/,/^}/p' "$REPO/install.sh"
  sed -n '/^install_to_canonical_path() {/,/^}/p' "$REPO/install.sh"
  printf 'install_to_canonical_path\n'
} >"$DRIVER"

seed_existing_install
printf 'n\n' | script -qec "bash $DRIVER" /dev/null >/dev/null 2>&1
check "install.sh: declining leaves the existing install in place" \
  "$([[ -f $DEST/USER_DATA.txt ]] && echo kept || echo DESTROYED)" "kept"

seed_existing_install
printf 'y\n' | script -qec "bash $DRIVER" /dev/null >/dev/null 2>&1
check "install.sh: accepting replaces it" \
  "$([[ -f $DEST/USER_DATA.txt ]] && echo stale || echo replaced)" "replaced"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
