#!/bin/bash
# Checks the install-shrinking migration against fixtures.
# Never touches the real install at ~/.local/share/hyprsimple.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788011545.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# An origin with enough history that dropping it is measurable, and a full
# clone of it standing in for an install.
# One `local` per line. On bash 5.3, `local a="$1" b="$a"` does not evaluate
# left to right: every right-hand side is expanded before any assignment lands,
# so `b` is built from an empty `a`. Under `set -u` that aborts the function
# inside its own command substitution and the caller captures an empty string.
make_install() {
  local name="$1"
  local origin="$TMP/$name-origin"
  local inst="$TMP/$name"
  # Name the branch explicitly. `git init` takes it from init.defaultBranch,
  # which is main on some machines and master on others, and a mismatch leaves
  # the bare repo's HEAD pointing at a branch this fixture never creates.
  git init -q --bare "$origin"
  git -C "$origin" symbolic-ref HEAD refs/heads/main
  git clone -q "$origin" "$TMP/$name-work" 2>/dev/null
  git -C "$TMP/$name-work" config user.email test@example.com
  git -C "$TMP/$name-work" config user.name test
  local i
  for i in 1 2 3 4 5; do
    head -c 200000 /dev/urandom >"$TMP/$name-work/blob.bin"
    printf 'v%s\n' "$i" >"$TMP/$name-work/f.txt"
    git -C "$TMP/$name-work" add -A
    git -C "$TMP/$name-work" commit -qm "commit $i"
  done
  git -C "$TMP/$name-work" push -q origin HEAD:refs/heads/main
  git -C "$TMP/$name-work" push -q origin HEAD:refs/heads/other
  git -C "$TMP/$name-work" tag -a v1 -m v1
  git -C "$TMP/$name-work" push -q origin v1
  git clone -q "$origin" "$inst"
  # The install clone commits too, in the unmerged-branch case. A GitHub runner
  # has no global git identity, so it needs its own.
  git -C "$inst" config user.email test@example.com
  git -C "$inst" config user.name test
  git -C "$inst" checkout -q main
  echo "$inst"
}

# Kilobytes, not megabytes. A fixture install is around 1200 KB, so measuring
# in whole megabytes would make "shrank by half" a coin flip.
size_kb() { du -sk "$1/.git" | cut -f1; }

# Every fixture path goes through this before any git command touches it. An
# empty path would make `git -C "$path"` operate on the current directory, which
# is the repository this suite runs from, so a fixture bug would corrupt the
# working tree rather than fail a check.
must_be_fixture() {
  if [[ -z ${1:-} || ! -d $1/.git || $1 != "$TMP"/* ]]; then
    printf 'fixture: refusing to use path [%s], expected a git repo under %s\n' "${1:-}" "$TMP" >&2
    exit 2
  fi
}

# ---- a fat install shrinks and can still pull ---------------------------

inst=$(make_install fat)
must_be_fixture "$inst"
before=$(size_kb "$inst")
HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >"$TMP/out_fat" 2>&1
after=$(size_kb "$inst")

if ((after * 2 <= before)); then pass "a fat install shrinks by at least half"
else fail "a fat install shrinks by at least half (before ${before}KB after ${after}KB)"; fi

check "the shrunk install is shallow" "$([[ -f $inst/.git/shallow ]] && echo yes || echo no)" yes
check "the working tree survives" "$(cat "$inst/f.txt")" "v5"
git -C "$inst" pull --ff-only -q origin main >/dev/null 2>&1
check "the shrunk install can still pull" "$?" "0"

# ---- a second run changes nothing ---------------------------------------

size_before_second=$(size_kb "$inst")
HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
check "migration is idempotent" "$(size_kb "$inst")" "$size_before_second"

# ---- an unmerged local branch is refused --------------------------------

inst=$(make_install unmerged)
must_be_fixture "$inst"
git -C "$inst" checkout -q -b mywork
printf 'unpushed work\n' >"$inst/mine.txt"
git -C "$inst" add -A
git -C "$inst" commit -qm "work nobody pushed"
git -C "$inst" checkout -q main
before=$(size_kb "$inst")
HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >"$TMP/out_unmerged" 2>&1

check "an unmerged branch survives" \
  "$(git -C "$inst" rev-parse --verify --quiet mywork >/dev/null && echo yes || echo no)" yes
check "nothing was reclaimed" "$(size_kb "$inst")" "$before"
if grep -q "mywork" "$TMP/out_unmerged"; then pass "the branch is named in the output"
else fail "the branch is named in the output"; fi

# ---- a dirty tree is refused --------------------------------------------

inst=$(make_install dirty)
must_be_fixture "$inst"
printf 'edited\n' >>"$inst/f.txt"
before=$(size_kb "$inst")
HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
check "a dirty install is left alone" "$(size_kb "$inst")" "$before"

# ---- a detached HEAD is refused -----------------------------------------

inst=$(make_install detached)
must_be_fixture "$inst"
git -C "$inst" checkout -q --detach HEAD
before=$(size_kb "$inst")
HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
check "a detached HEAD is left alone" "$(size_kb "$inst")" "$before"

# ---- a missing install is a no-op ---------------------------------------

HYPRSIMPLE_PATH="$TMP/nothing-here" bash "$MIGRATION" >/dev/null 2>&1
check "a missing install exits 0" "$?" "0"

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
