#!/bin/bash
# Checks the migration runner's failure path.
#
# On a failure it asked "Skip it and continue? (y/N)" and read the answer from
# stdin. bootstrap.sh runs this runner, and its documented install is
#
#   curl -fsSL .../bootstrap.sh | bash
#
# where stdin is the installer itself. So the read did not wait for a person:
# it took the next line of bootstrap.sh as the answer, and that line never ran.
#
# Demonstrated with the version on main, piped into bash: the line after the
# runner call was consumed and never printed, while the one after it did.
#
# bootstrap.sh already guards its own single prompt this way and says why. The
# runner it calls did not.
#
# Nothing here touches the real migration state: every run gets its own HOME
# and its own HYPRSIMPLE_PATH.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$REPO/.local/bin/hyprsimple-migrate.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}
for helper in pass fail check; do
  declare -F "$helper" >/dev/null || { printf 'not ok - helper %s missing\n' "$helper" >&2; exit 1; }
done

# A fixture install holding one migration that behaves as the test arranges.
make_install() {
  local dir="$1" body="$2"
  rm -rf "${dir:?}"
  mkdir -p "$dir/migrations"
  printf '%s\n' "$body" >"$dir/migrations/1700000000.sh"
}

state_dir() { printf '%s' "$1/.local/state/hyprsimple/migrations"; }

# ---- a failing migration under a pipe does not eat the caller --------------
#
# The caller is a script piped into bash, which is what curl-pipe is. If the
# runner reads, it takes a line of that script and the line never runs.

INST="$TMP/install"
make_install "$INST" 'echo "this migration fails"
exit 1'

H="$TMP/home-pipe"; mkdir -p "$H"
CALLER="$TMP/caller.sh"
cat >"$CALLER" <<CALLEREOF
echo CALLER-BEFORE
HOME="$H" HYPRSIMPLE_PATH="$INST" bash "$RUNNER" || true
echo CALLER-AFTER-ONE
echo CALLER-AFTER-TWO
CALLEREOF

out=$(bash <"$CALLER" 2>&1)

check "the line after the runner still runs when a migration fails under a pipe" \
  "$(printf '%s\n' "$out" | grep -c '^CALLER-AFTER-ONE$')" "1"
check "and so does the one after that" \
  "$(printf '%s\n' "$out" | grep -c '^CALLER-AFTER-TWO$')" "1"
check "the failure is still reported" \
  "$(printf '%s\n' "$out" | grep -c 'failed')" "1"
check "and it says nothing was there to answer" \
  "$(printf '%s\n' "$out" | grep -c 'Nothing is attached to answer')" "1"
check "and points at running it from a terminal" \
  "$(printf '%s\n' "$out" | grep -c 'from a terminal')" "1"

# The important half: a failure with nobody watching must not be recorded as a
# decision to skip. That marker means "never run this again".
check "a failed migration is not marked skipped when nobody could answer" \
  "$(find "$(state_dir "$H")/skipped" -type f 2>/dev/null | wc -l | tr -d ' ')" "0"
check "and not marked done either" \
  "$(find "$(state_dir "$H")" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')" "0"

# The prompt is what did the damage, so the absence of a read is checked in the
# code as well as in the behaviour above.
check "the runner asks nothing when stdin is not a terminal" \
  "$(sed 's/#.*//' "$RUNNER" | grep -c '\[\[ ! -t 0 \]\]')" "1"
check "and the guard sits before the read, not after it" \
  "$([[ $(sed 's/#.*//' "$RUNNER" | grep -n '\[\[ ! -t 0 \]\]' | cut -d: -f1) -lt \
        $(sed 's/#.*//' "$RUNNER" | grep -n 'read -rp' | cut -d: -f1) ]] && echo before || echo after)" \
  "before"

# ---- anti-vacuity: the runner still runs migrations at all -----------------
#
# Every check above is about a failure. A runner that did nothing would satisfy
# them for the wrong reason.

INST_OK="$TMP/install-ok"
make_install "$INST_OK" 'printf "ran\n" >"$MIGRATION_WITNESS"'
H_OK="$TMP/home-ok"; mkdir -p "$H_OK"
WITNESS="$TMP/witness"; rm -f "$WITNESS"

MIGRATION_WITNESS="$WITNESS" HOME="$H_OK" HYPRSIMPLE_PATH="$INST_OK" \
  bash "$RUNNER" >/dev/null 2>&1
check "a migration that succeeds is run" \
  "$([[ -f $WITNESS ]] && echo ran || echo skipped)" "ran"
check "and marked done, so it never runs twice" \
  "$([[ -f $(state_dir "$H_OK")/1700000000.sh ]] && echo marked || echo unmarked)" "marked"

rm -f "$WITNESS"
MIGRATION_WITNESS="$WITNESS" HOME="$H_OK" HYPRSIMPLE_PATH="$INST_OK" \
  bash "$RUNNER" >/dev/null 2>&1
check "and really does not run again" \
  "$([[ -f $WITNESS ]] && echo ran || echo skipped)" "skipped"

# ---- bootstrap.sh guards its own prompt the same way ------------------------
#
# The runner's guard is only half the story if the caller drops its own.
check "bootstrap.sh still guards its prompt for the same reason" \
  "$(sed 's/#.*//' "$REPO/bootstrap.sh" | grep -c '\[\[ -t 0 \]\] || return 0')" "1"
check "and bootstrap.sh still calls the runner, which is what makes this matter" \
  "$(sed 's/#.*//' "$REPO/bootstrap.sh" | grep -c 'hyprsimple-migrate.sh')" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
