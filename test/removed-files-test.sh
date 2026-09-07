#!/bin/bash
# Two files hyprsimple shipped that nothing read.
#
# themes/<name>/btop.theme, fifteen of them. theme-switcher.sh copies
# themes/<name>/generated/btop.theme, rendered from templates/btop.theme.tpl,
# and never looks at the file beside it. Measured on a live install: the file
# in the theme directory differs from the one btop is using, and only one of
# the fifteen carries the full key set. Editing one changed nothing.
#
# .bashrc at the repository root. install.sh iterates "$DOTFILES_DIR/.config"/*
# only, so nothing has copied it since 9aaa1e4 removed the line that did:
#
#   ln -sf "$DOTFILES_DIR/.bashrc" "$HOME/.bashrc"
#
# That line is why deleting the file needed a migration rather than just a
# delete. It pointed the home file at whatever directory the repository was
# cloned into, which is not the canonical install path and is somewhere
# hyprsimple never looks again, so removing the file would leave an old install
# with a dangling rc: bash starting with no aliases, no starship and no zoxide,
# silently.
#
# Nothing here runs an installer. The migration runs against throwaway homes.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788714829.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- gone from the repository -------------------------------------------------

check "no theme ships a btop.theme any more" \
  "$(find "$REPO/.config/hypr/themes" -maxdepth 2 -name btop.theme | wc -l | tr -d ' ')" "0"
check "and the repository root ships no .bashrc" \
  "$([[ -f $REPO/.bashrc ]] && echo present || echo gone)" "gone"

# The thing that does the work is still there, or this removed a feature rather
# than a leftover.
check "the btop template is still shipped" \
  "$([[ -f $REPO/.config/hypr/themes/templates/btop.theme.tpl ]] && echo yes || echo no)" "yes"
# In hyprsimple-theme-deliver.sh, which is where the delivery moved when it
# became one function shared with hyprsimple-update.sh. The update used to
# carry its own shorter list and never delivered btop.theme at all.
check "and the shared delivery still installs the rendered one" \
  "$(grep -c 'GEN/btop.theme' "$REPO/.local/bin/hyprsimple-theme-deliver.sh")" "2"
check "and bashrc.sh, which the shell actually sources, is still shipped" \
  "$([[ -f $REPO/.local/bin/bashrc.sh ]] && echo yes || echo no)" "yes"
check "and terminal.sh still wires it into a real ~/.bashrc" \
  "$(grep -c 'BIN_DIR/bashrc.sh' "$REPO/.local/bin/terminal.sh")" "1"

# --- the migration clears what is already installed ---------------------------

run_migration() { HOME="$1" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" >"$TMP/out" 2>&1; }

H="$TMP/home"
setup() { rm -rf "${TMP:?}/home"; mkdir -p "$H/.config/hypr/themes"; }

# A committed copy of what was shipped, not `git show`. CI checks out shallow,
# so a suite asking git for a file this change deletes is handed nothing, and
# suite-hygiene-test.sh fails any suite that tries. It caught the first version
# of this one.
PRE="$REPO/test/fixtures/pre-removal"

setup
mkdir -p "$H/.config/hypr/themes/nord"
cp "$PRE/nord-btop.theme" "$H/.config/hypr/themes/nord/btop.theme"
check "the fixture is one of the checksums the migration records" \
  "$(grep -c "$(md5sum "$PRE/nord-btop.theme" | cut -d' ' -f1)" "$MIGRATION")" "1"

mkdir -p "$H/.config/hypr/themes/mine"
printf 'my own file\n' >"$H/.config/hypr/themes/mine/btop.theme"

run_migration "$H"
check "a shipped btop.theme is removed" \
  "$([[ -f $H/.config/hypr/themes/nord/btop.theme ]] && echo present || echo gone)" "gone"
check "one somebody wrote is left alone" \
  "$(cat "$H/.config/hypr/themes/mine/btop.theme")" "my own file"
check "and named, so they know nothing reads it" \
  "$(grep -c 'themes/mine/btop.theme' "$TMP/out")" "1"

# --- and repairs a ~/.bashrc that pointed into a checkout ---------------------

setup
mkdir -p "$H/clone"
printf '# If not running interactively, do nothing\nsource "$HOME/.local/bin/bashrc.sh"\n' \
  >"$H/clone/.bashrc"
ln -sfn "$H/clone/.bashrc" "$H/.bashrc"
printf 'MY ORIGINAL BASHRC\n' >"$H/.bashrc.backup"

run_migration "$H"
check "a symlinked ~/.bashrc becomes a real file" \
  "$([[ -L $H/.bashrc ]] && echo link || echo file)" "file"
check "which still sources hyprsimple's shell init" \
  "$(grep -c 'bashrc.sh' "$H/.bashrc")" "1"
check "and keeps the interactive guard, so a script does not source it" \
  "$(grep -c 'not running interactively' "$H/.bashrc")" "1"
check "the pre-hyprsimple backup is left where it was" \
  "$(cat "$H/.bashrc.backup")" "MY ORIGINAL BASHRC"
check "and is pointed out" "$(grep -c 'bashrc.backup' "$TMP/out")" "1"

# A real ~/.bashrc is never touched.
setup
printf '# mine\n' >"$H/.bashrc"
run_migration "$H"
check "a real ~/.bashrc is left exactly as it is" "$(cat "$H/.bashrc")" "# mine"

# Nor is a symlink that points somewhere else entirely.
setup
printf 'someone elses\n' >"$H/other-rc"
ln -sfn "$H/other-rc" "$H/.bashrc"
run_migration "$H"
check "a symlink to something that is not a .bashrc is left alone" \
  "$([[ -L $H/.bashrc ]] && echo link || echo file)" "link"

# --- and an already clean home is silent --------------------------------------

setup
run_migration "$H"
check "a home with none of this says nothing beyond its title" \
  "$(grep -vc 'Clear out two files' "$TMP/out")" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
