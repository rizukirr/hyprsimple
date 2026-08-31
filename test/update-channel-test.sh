#!/bin/bash
# Checks the update channels in hyprsimple-update.sh: a bare run continues the
# channel the install is already on, --stable moves it to the newest release
# tag, and a branch name moves it to that branch and keeps it there.
#
# Everything happens against throwaway file:// origins under a temp directory.
# The real install at ~/.local/share/hyprsimple is never read or written, and
# HOME is redirected so the script's own helper-script refresh cannot escape.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO/.local/bin/hyprsimple-update.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# hyprsimple-update ends by reloading Hyprland and running the migration
# runner. Neither belongs in this test, and pgrep unstubbed would find the real
# compositor on the machine running the suite.
STUB="$TMP/stub"
mkdir -p "$STUB"
printf '#!/bin/bash\nexit 1\n' >"$STUB/pgrep"
printf '#!/bin/bash\nexit 0\n' >"$STUB/hyprctl"
chmod +x "$STUB/pgrep" "$STUB/hyprctl"

FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.local/bin"
printf '#!/bin/bash\nexit 0\n' >"$FAKE_HOME/.local/bin/hyprsimple-migrate.sh"
chmod +x "$FAKE_HOME/.local/bin/hyprsimple-migrate.sh"

ORIGIN="$TMP/origin.git"
WORK="$TMP/work"
INSTALL="$TMP/install"

commit_version() {
  printf '%s\n' "$1" >"$WORK/version"
  git -C "$WORK" add version
  git -C "$WORK" commit -qm "version $1"
}

git init -q --bare "$ORIGIN"
git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main
git clone -q "$ORIGIN" "$WORK" 2>/dev/null
git -C "$WORK" config user.email test@example.com
git -C "$WORK" config user.name test

commit_version 0.1.0
git -C "$WORK" tag v0.1.0
commit_version 0.2.3
# Deliberately unprefixed, matching the real 0.2.3 tag. The sort must order it
# by number, not put it below every v-prefixed tag.
git -C "$WORK" tag 0.2.3
commit_version 0.3.0
git -C "$WORK" tag v0.3.0
commit_version 0.4.0-dev
git -C "$WORK" push -q origin main --tags

# The install as the shrinking migration leaves it: shallow, and with every tag
# ref deleted. Tag resolution has to work from this state.
git clone -q --depth 1 "file://$ORIGIN" "$INSTALL"
git -C "$INSTALL" for-each-ref --format='%(refname)' refs/tags |
  while read -r r; do git -C "$INSTALL" update-ref -d "$r"; done

run_update() {
  HOME="$FAKE_HOME" HYPRSIMPLE_PATH="$INSTALL" PATH="$STUB:$PATH" \
    bash "$UPDATE" "$@" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
installed_version() { cat "$INSTALL/version"; }
head_state() { git -C "$INSTALL" symbolic-ref --quiet --short HEAD || echo DETACHED; }

check "fixture starts on main" "$(head_state)" main
check "fixture starts at main tip" "$(installed_version)" 0.4.0-dev
check "fixture has no local tags" "$(git -C "$INSTALL" tag | wc -l)" 0

# --- bare run on a branch stays on that branch ------------------------------
run_update
check "bare run on a branch exits 0" "$(rc)" 0
check "bare run on a branch stays on main" "$(head_state)" main

# --- --stable moves to the newest tag ---------------------------------------
run_update --stable
check "--stable exits 0" "$(rc)" 0
check "--stable detaches HEAD" "$(head_state)" DETACHED
check "--stable picks the newest tag, not the newest v-tag" "$(installed_version)" 0.3.0
check "--stable lands exactly on the tag" "$(git -C "$INSTALL" describe --tags)" v0.3.0
if grep -q "Leaving branch main for releases" "$TMP/out"; then
  pass "--stable says it is leaving the branch"
else fail "--stable says it is leaving the branch"; fi

# --- a bare run on a tag follows new releases -------------------------------
commit_version 0.5.0
git -C "$WORK" tag v0.5.0
git -C "$WORK" push -q origin main --tags

run_update
check "bare run on a tag exits 0" "$(rc)" 0
check "bare run on a tag stays detached" "$(head_state)" DETACHED
check "bare run on a tag moves to the new release" "$(installed_version)" 0.5.0

# --- a re-pointed release reaches an install already holding that tag -------
# git refuses to update an existing tag without --force, prints
# "! [rejected] (would clobber existing tag)", and still exits 0. Without the
# force flag this check passes its exit code and fails on content.
commit_version 0.5.0-hotfix
git -C "$WORK" tag -f v0.5.0 >/dev/null 2>&1
git -C "$WORK" push -q --force origin v0.5.0

run_update
check "a moved tag exits 0" "$(rc)" 0
check "a moved tag actually updates the install" "$(installed_version)" 0.5.0-hotfix

# --- a branch argument moves back, and sticks -------------------------------
commit_version 0.6.0-dev
git -C "$WORK" push -q origin main

run_update main
check "branch argument exits 0" "$(rc)" 0
check "branch argument attaches HEAD" "$(head_state)" main
check "branch argument lands on the branch tip" "$(installed_version)" 0.6.0-dev

commit_version 0.7.0-dev
git -C "$WORK" push -q origin main
run_update
check "the branch choice sticks across a bare run" "$(head_state)" main
check "a later bare run pulls the branch, not the tag" "$(installed_version)" 0.7.0-dev

# --- an arbitrary branch, not just main -------------------------------------
git -C "$WORK" checkout -q -b feature-x
commit_version 0.8.0-feature
git -C "$WORK" push -q origin feature-x
git -C "$WORK" checkout -q main

run_update feature-x
check "an arbitrary branch is accepted" "$(rc)" 0
check "an arbitrary branch is checked out" "$(head_state)" feature-x
check "an arbitrary branch brings its content" "$(installed_version)" 0.8.0-feature

# --- failure modes ----------------------------------------------------------
before=$(git -C "$INSTALL" rev-parse HEAD)
run_update no-such-branch
check "an unknown branch fails" "$(rc)" 1
check "an unknown branch leaves the install alone" "$(git -C "$INSTALL" rev-parse HEAD)" "$before"
if grep -q "no branch called 'no-such-branch'" "$TMP/out"; then
  pass "an unknown branch is named in the error"
else fail "an unknown branch is named in the error"; fi

run_update --nonsense
check "an unknown option fails" "$(rc)" 1
run_update --help
check "--help exits 0" "$(rc)" 0

# --- the shrink must survive all of it --------------------------------------
check "the install is still shallow" "$(git -C "$INSTALL" rev-parse --is-shallow-repository)" true

if ((failures > 0)); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
