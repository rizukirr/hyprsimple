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
must_be_fixture "$FAKE_HOME"
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
# A clone that produced nothing makes every later check pass against an empty
# tree, which is how four checks once reported ok while testing nothing.
[[ -e $INSTALL/.git ]] || { printf 'not ok - fixture clone produced nothing\n' >&2; exit 1; }
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
# The branch has to be named, whatever the wording around it. The message used
# to assert the cause outright, "origin has no branch called X", and a fetch
# that stalled produced that same line about a branch that exists. It says which
# fetch failed and offers both causes now.
if grep -q "no-such-branch" "$TMP/out"; then
  pass "an unknown branch is named in the error"
else fail "an unknown branch is named in the error"; fi
if grep -q "no branch by that name" "$TMP/out"; then
  pass "and a missing branch is still offered as the cause"
else fail "and a missing branch is still offered as the cause"; fi

run_update --nonsense
check "an unknown option fails" "$(rc)" 1
run_update --help
check "--help exits 0" "$(rc)" 0

# --- the shrink must survive all of it --------------------------------------
check "the install is still shallow" "$(git -C "$INSTALL" rev-parse --is-shallow-repository)" true

# ---- a stalled origin stops instead of hanging -------------------------------
#
# The three git calls that reach origin were unbounded. A connection that
# stalls mid transfer left "Pulling latest hyprsimple..." on screen with no
# output, no timeout and nothing to say whether it was slow or wedged. Seen
# doing exactly that on a real machine: an established connection to github
# with nothing moving through it for two and a half minutes, while curl to the
# same host answered in under a second, until it was interrupted by hand.
#
# Driven against a server that accepts and then sends nothing, which is that
# stall, rather than against a refused or missing port. A refusal fails fast on
# its own and would prove nothing about the guard.

STALL_LOG="$TMP/stall-server.log"
STALL_PIDFILE="$TMP/stall-server.pid"
cat >"$TMP/stallserver.py" <<'PYEOF'
import socket, sys
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(("127.0.0.1", 0))
s.listen(16)
print(s.getsockname()[1], flush=True)
held = []
while True:
    c, _ = s.accept()
    held.append(c)  # accepted, never answered, never closed
PYEOF

python3 "$TMP/stallserver.py" >"$STALL_LOG" 2>/dev/null &
printf '%s' "$!" >"$STALL_PIDFILE"
# By recorded pid, never by pattern. pkill -f matches the command line of
# whatever shell is running this suite, and a pattern that appears in that
# command line kills the suite itself.
kill_stall_server() {
  local pid
  pid=$(cat "$STALL_PIDFILE" 2>/dev/null) || return 0
  [[ -n $pid ]] && kill "$pid" 2>/dev/null
  : >"$STALL_PIDFILE"
}
trap 'kill_stall_server; rm -rf "$TMP"' EXIT

stall_port=""
for _ in $(seq 1 50); do
  stall_port=$(head -1 "$STALL_LOG" 2>/dev/null)
  [[ -n $stall_port ]] && break
  sleep 0.1
done

if [[ -z $stall_port ]]; then
  fail "the stalling server did not start, so the guard is not being tested"
else
  pass "a stalling server is listening on port $stall_port"

  stall_install="$TMP/stall-install"
  must_be_fixture "$stall_install"
  git init -q "$stall_install"
  git -C "$stall_install" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$stall_install" branch -M main
  git -C "$stall_install" remote add origin "http://127.0.0.1:$stall_port/x.git"

  started=$(date +%s)
  HOME="$FAKE_HOME" HYPRSIMPLE_PATH="$stall_install" PATH="$STUB:$PATH" \
    HYPRSIMPLE_GIT_STALL_SECONDS=3 HYPRSIMPLE_GIT_STALL_BYTES=1000 \
    HYPRSIMPLE_GIT_ATTEMPTS=2 \
    timeout 40 bash "$UPDATE" main >"$TMP/stall-out" 2>&1
  stall_rc=$?
  elapsed=$(( $(date +%s) - started ))

  check "a stalled origin does not hang the update" \
    "$([[ $stall_rc == 124 ]] && echo hung || echo stopped)" "stopped"
  check "and it stops near the guard rather than much later (${elapsed}s)" \
    "$([[ $elapsed -lt 20 ]] && echo prompt || echo late)" "prompt"
  check "and exits non-zero" \
    "$([[ $stall_rc != "0" ]] && echo nonzero || echo zero)" "nonzero"
  check "and says the fetch did not complete" \
    "$(grep -c 'did not complete' "$TMP/stall-out")" "1"
  check "and names stalling as the thing to look at" \
    "$(grep -c 'stalling rather than failing' "$TMP/stall-out")" "1"

  # The half that matters most: a fetch that never got through must not leave
  # the run reporting success. The first version of the retry read $? on the
  # line after an if whose condition had failed, which in bash is 0, so it
  # returned success for a fetch that failed every attempt and the script went
  # on to print "hyprsimple is up to date" against a repository it had not
  # updated. That is worse than the hang it replaced.
  check "a fetch that never got through is not reported as up to date" \
    "$(grep -c 'up to date' "$TMP/stall-out")" "0"
  check "and the run does not claim a version it did not fetch" \
    "$(grep -c 'Now on hyprsimple' "$TMP/stall-out")" "0"

  # It really did try more than once, or the retry is not being exercised.
  check "and it tried again before giving up" \
    "$(grep -c 'Trying again' "$TMP/stall-out")" "1"

  # Without the guard the same fetch is still running when the cap fires, which
  # is what makes the checks above about the guard and not about the server.
  started=$(date +%s)
  timeout 8 git -C "$stall_install" fetch --quiet origin main >/dev/null 2>&1
  bare_rc=$?
  check "the same fetch unguarded is still hanging when it is cut off" \
    "$([[ $bare_rc == 124 ]] && echo hanging || echo stopped)" "hanging"
  check "and it used the whole window rather than failing early" \
    "$([[ $(( $(date +%s) - started )) -ge 7 ]] && echo whole || echo early)" "whole"

  kill_stall_server
fi

# All three calls that reach origin go through the guard, not just the one the
# checks above happen to exercise.
update_code() { sed 's/^[[:space:]]*#.*//' "$UPDATE"; }
check "no call to origin bypasses the guard" \
  "$(update_code | grep -cE 'git -C "\$HYPRSIMPLE_PATH" (fetch|ls-remote)')" "0"
check "and the guard is used by all three of them" \
  "$(update_code | grep -cE 'git_net (fetch|ls-remote)')" "3"
check "the number of attempts is bounded and overridable" \
  "$(update_code | grep -c 'HYPRSIMPLE_GIT_ATTEMPTS')" "1"
check "and it sets both halves of git's low speed check" \
  "$(update_code | grep -c 'http.lowSpeedLimit')" "1"
check "and the time half too" \
  "$(update_code | grep -c 'http.lowSpeedTime')" "1"

if ((failures > 0)); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
