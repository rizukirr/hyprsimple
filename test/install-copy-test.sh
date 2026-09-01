#!/bin/bash
# Checks that the installer copies tracked content only.
#
# Extracts install_to_canonical_path from install.sh and runs it against
# fixtures, so the test exercises the real function rather than a copy of it.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# An empty or unexpected path turns the rm and cp calls below into operations on
# the real home directory. Every fixture path goes through this first.
must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'not ok - refusing to operate outside the fixture: %s\n' "${1:-<empty>}" >&2
    exit 1
  fi
}

failures=0

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() { if [[ $2 == "$3" ]]; then pass "$1"; else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi; }

# The function depends on these globals and nothing else.
# shellcheck disable=SC2034  # read by the bootstrap.sh function eval'd below
RED='' GREEN='' YELLOW='' NC=''
eval "$(sed -n '/^install_to_canonical_path() {/,/^}/p' "$REPO/install.sh")"
eval "$(sed -n '/^copy_source_to_canonical_path() {/,/^}/p' "$REPO/bootstrap.sh")"

# ---- fixture: a checkout carrying ignored paths -------------------------

build_fixture() {
  local src="$1"
  mkdir -p "$src"
  git -C "$src" init -q
  git -C "$src" config user.email test@example.com
  git -C "$src" config user.name test
  git -C "$src" remote add origin https://github.com/rizukirr/hyprsimple

  mkdir -p "$src/.config" "$src/.local/bin"
  printf 'tracked\n' >"$src/install.sh"
  printf 'tracked\n' >"$src/.config/kept.conf"
  printf '#!/bin/bash\n' >"$src/.local/bin/kept.sh"
  chmod 0755 "$src/.local/bin/kept.sh"
  ln -sf kept.conf "$src/.config/link.conf"
  printf 'ignored-dir/\nscratch/\n' >"$src/.gitignore"
  git -C "$src" add -A
  git -C "$src" commit -qm init

  # Everything below is ignored and must not reach the install.
  mkdir -p "$src/ignored-dir" "$src/scratch"
  printf 'junk\n' >"$src/ignored-dir/junk.txt"
  printf 'junk\n' >"$src/scratch/notes.md"
  git -C "$src/ignored-dir" init -q vendored
  git -C "$src/ignored-dir/vendored" config user.email test@example.com
  git -C "$src/ignored-dir/vendored" config user.name test
  printf 'x\n' >"$src/ignored-dir/vendored/file"
  git -C "$src/ignored-dir/vendored" add -A
  git -C "$src/ignored-dir/vendored" commit -qm x
}

DOTFILES_DIR="$TMP/src"
HYPRSIMPLE_PATH="$TMP/install"
must_be_fixture "$DOTFILES_DIR"
must_be_fixture "$HYPRSIMPLE_PATH"
build_fixture "$DOTFILES_DIR"
install_to_canonical_path >/dev/null

check "ignored directory is not installed"    "$([[ -e $HYPRSIMPLE_PATH/ignored-dir ]] && echo present || echo absent)" absent
check "nested git repo is not installed"      "$([[ -e $HYPRSIMPLE_PATH/ignored-dir/vendored ]] && echo present || echo absent)" absent
check "second ignored directory is absent"    "$([[ -e $HYPRSIMPLE_PATH/scratch ]] && echo present || echo absent)" absent
check "tracked config is installed"           "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes
check "git directory survives"                "$([[ -d $HYPRSIMPLE_PATH/.git ]] && echo yes || echo no)" yes
check "origin survives"                       "$(git -C "$HYPRSIMPLE_PATH" remote get-url origin)" https://github.com/rizukirr/hyprsimple
check "executable bit survives"               "$(stat -c%a "$HYPRSIMPLE_PATH/.local/bin/kept.sh")" 755
check "symlink survives as a symlink"         "$([[ -L $HYPRSIMPLE_PATH/.config/link.conf ]] && echo yes || echo no)" yes
check "install tree is clean, so it can pull" "$(git -C "$HYPRSIMPLE_PATH" status --porcelain)" ""

# ---- uncommitted changes are reported and not installed ------------------

DOTFILES_DIR="$TMP/dirty"
HYPRSIMPLE_PATH="$TMP/dirty-install"
build_fixture "$DOTFILES_DIR"
printf 'uncommitted\n' >>"$DOTFILES_DIR/.config/kept.conf"
output="$(install_to_canonical_path)"

if grep -q "will not be installed" <<<"$output"; then
  pass "dirty source is reported"
else
  fail "dirty source is reported"
fi
check "dirty source installs HEAD, not the edit" "$(cat "$HYPRSIMPLE_PATH/.config/kept.conf")" tracked
check "install from a dirty source is still clean" "$(git -C "$HYPRSIMPLE_PATH" status --porcelain)" ""

# ---- a source that is not a git repository still installs ----------------

DOTFILES_DIR="$TMP/plain"
HYPRSIMPLE_PATH="$TMP/plain-install"
mkdir -p "$DOTFILES_DIR/.config"
printf 'tracked\n' >"$DOTFILES_DIR/install.sh"
printf 'tracked\n' >"$DOTFILES_DIR/.config/kept.conf"
install_to_canonical_path >/dev/null
check "non-repo source still installs" "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes

# ---- a clean source produces no warning ----------------------------------

DOTFILES_DIR="$TMP/clean"
HYPRSIMPLE_PATH="$TMP/clean-install"
build_fixture "$DOTFILES_DIR"
output="$(install_to_canonical_path)"
if grep -q "will not be installed" <<<"$output"; then
  fail "clean source produces no warning"
else
  pass "clean source produces no warning"
fi

# ---- bootstrap.sh does the same thing ------------------------------------

SOURCE_DIR="$TMP/bsrc"
HYPRSIMPLE_PATH="$TMP/bsrc-install"
build_fixture "$SOURCE_DIR"
copy_source_to_canonical_path >/dev/null

check "bootstrap: ignored directory is not installed" "$([[ -e $HYPRSIMPLE_PATH/ignored-dir ]] && echo present || echo absent)" absent
check "bootstrap: nested git repo is not installed"   "$([[ -e $HYPRSIMPLE_PATH/ignored-dir/vendored ]] && echo present || echo absent)" absent
check "bootstrap: tracked config is installed"        "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes
check "bootstrap: git directory survives"             "$([[ -d $HYPRSIMPLE_PATH/.git ]] && echo yes || echo no)" yes
check "bootstrap: install tree is clean"              "$(git -C "$HYPRSIMPLE_PATH" status --porcelain)" ""

SOURCE_DIR="$TMP/bplain"
HYPRSIMPLE_PATH="$TMP/bplain-install"
mkdir -p "$SOURCE_DIR/.config"
printf 'tracked\n' >"$SOURCE_DIR/.config/kept.conf"
copy_source_to_canonical_path >/dev/null
check "bootstrap: non-repo source still installs" "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes

# ---- a repository with no commits does not abort the install -------------

DOTFILES_DIR="$TMP/nocommit"
HYPRSIMPLE_PATH="$TMP/nocommit-install"
mkdir -p "$DOTFILES_DIR/.config"
git -C "$DOTFILES_DIR" init -q
printf 'tracked\n' >"$DOTFILES_DIR/.config/kept.conf"
install_to_canonical_path >/dev/null
check "empty repo still installs" "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes

# ---- the prompt is skipped when stdin is not a terminal ------------------

DOTFILES_DIR="$TMP/notty"
HYPRSIMPLE_PATH="$TMP/notty-install"
build_fixture "$DOTFILES_DIR"
printf 'uncommitted\n' >>"$DOTFILES_DIR/.config/kept.conf"
if install_to_canonical_path </dev/null >/dev/null 2>&1; then
  pass "dirty source does not prompt when stdin is not a terminal"
else
  fail "dirty source does not prompt when stdin is not a terminal"
fi
check "non-terminal dirty install still happened" "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes

# ---- bootstrap: shallow clone, archive, then unshallow -------------------

origin_repo="$TMP/origin"
mkdir -p "$origin_repo/.config"
git -C "$origin_repo" init -q
git -C "$origin_repo" config user.email test@example.com
git -C "$origin_repo" config user.name test
printf 'one\n' >"$origin_repo/.config/kept.conf"
printf 'x\n' >"$origin_repo/install.sh"
git -C "$origin_repo" add -A
git -C "$origin_repo" commit -qm one
printf 'two\n' >>"$origin_repo/.config/kept.conf"
git -C "$origin_repo" commit -qam two

SOURCE_DIR="$TMP/shallow"
HYPRSIMPLE_PATH="$TMP/shallow-install"
git clone -q --depth 1 "file://$origin_repo" "$SOURCE_DIR"
# A clone that produced nothing makes every later check pass against an empty
# tree, which is how four checks once reported ok while testing nothing.
[[ -e $SOURCE_DIR/.git ]] || { printf 'not ok - fixture clone produced nothing\n' >&2; exit 1; }
check "clone under test is actually shallow" "$([[ -f $SOURCE_DIR/.git/shallow ]] && echo yes || echo no)" yes
copy_source_to_canonical_path >/dev/null
check "shallow source installs tracked content" "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes
check "shallow install tree is clean" "$(git -C "$HYPRSIMPLE_PATH" status --porcelain)" ""
git -C "$HYPRSIMPLE_PATH" fetch --unshallow origin >/dev/null 2>&1
check "unshallow leaves a full clone" "$([[ -f $HYPRSIMPLE_PATH/.git/shallow ]] && echo shallow || echo full)" full

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
