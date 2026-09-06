#!/bin/bash
# hyprsimple-dev-add-migration.sh named a migration after the last commit's
# timestamp, on the stated claim that this
#
#   sorts after every existing migration but before anything written later
#
# and the first half of that does not hold. hyprsimple-migrate.sh runs
# migrations in glob order, which for digits is numeric order, so the name
# decides what runs first on every machine. A migration added by hand carries
# whatever number was typed, and 1788644900 sat about six hours ahead of every
# commit date in the repository. The next migration this tool named would have
# sorted before it and run first, while the tool said the opposite.
#
# Harmless between two migrations that do not touch the same thing. Not
# harmless between two that do, and the tool is the only thing a contributor
# reads before trusting the order.
#
# Nothing here runs a migration. The tool is pointed at throwaway git
# repositories and only its choice of filename is measured.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$REPO/.local/bin/hyprsimple-dev-add-migration.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# A repository whose single commit carries a chosen date, holding the migration
# names it is given.
make_repo() {
  local commit_date="$1"; shift
  local dir="$TMP/repo"
  rm -rf "${TMP:?}/repo"
  mkdir -p "$dir/migrations"
  # git records no empty directory, so with no migrations there would be
  # nothing to commit, no commit to date, and the tool would exit before
  # choosing anything. The first version of this suite read that as the tool
  # returning an empty name.
  printf 'seed\n' >"$dir/README"
  for name in "$@"; do printf 'echo x\n' >"$dir/migrations/$name.sh"; done
  (
    cd "$dir" || exit 1
    git init -q .
    git config user.email t@example.com
    git config user.name t
    git add -A
    GIT_AUTHOR_DATE="@$commit_date +0000" GIT_COMMITTER_DATE="@$commit_date +0000" \
      git commit -q -m seed
  ) >/dev/null 2>&1
  printf '%s' "$dir"
}

# Prints the basename the tool chose, without its extension.
name_chosen() {
  local dir="$1" out
  out=$( cd "$dir" && bash "$TOOL" --no-edit 2>/dev/null )
  basename "$out" .sh
}

# --- the ordinary case is unchanged ------------------------------------------

dir=$(make_repo 1788000000 1787000000 1787500000)
check "with every migration older than the commit, the commit date is used" \
  "$(name_chosen "$dir")" "1788000000"

# --- a migration ahead of every commit ---------------------------------------
#
# This is the case that was live in the repository.

dir=$(make_repo 1788000000 1787000000 1788644900)
chosen=$(name_chosen "$dir")
check "a migration numbered ahead of the commit is sorted after, not before" \
  "$chosen" "1788644901"
if (( chosen > 1788644900 )); then
  pass "so the tool's own claim about ordering holds"
else
  fail "chose $chosen, which runs before the existing 1788644900"
fi

# --- and the ordering is the one the runner actually uses --------------------
#
# Measured with a glob rather than assumed, because the claim is about what
# hyprsimple-migrate.sh does, and what it does is expand *.sh.
printf 'echo x\n' >"$dir/migrations/$chosen.sh"
last=$(for m in "$dir/migrations"/*.sh; do basename "$m" .sh; done | tail -1)
check "the new migration is last in the order the runner globs" "$last" "$chosen"

# --- exactly equal, which the comparison has to include ----------------------

dir=$(make_repo 1788000000 1788000000)
check "a migration equal to the commit date is still sorted after" \
  "$(name_chosen "$dir")" "1788000001"

# --- names that are not numbers ----------------------------------------------

dir=$(make_repo 1788000000 1787000000 notanumber)
check "a non-numeric name is skipped rather than compared" \
  "$(name_chosen "$dir")" "1788000000"

# --- an empty migrations directory -------------------------------------------

dir=$(make_repo 1788000000)
check "with no migrations at all the commit date is used" \
  "$(name_chosen "$dir")" "1788000000"

# --- the file it writes is usable --------------------------------------------

dir=$(make_repo 1788000000 1787000000)
chosen=$(name_chosen "$dir")
check "the migration it creates parses as bash" \
  "$(bash -n "$dir/migrations/$chosen.sh" 2>&1 && echo ok)" "ok"

# Running twice in a row must not collide. There is no commit between them, so
# the commit date is identical and only the highest existing name moves.
second=$(name_chosen "$dir")
if [[ $second != "$chosen" ]] && (( second > chosen )); then
  pass "a second run in the same commit picks a later name, not the same one"
else
  fail "the second run chose $second against the first's $chosen"
fi

# --- what makes glob order equal numeric order -------------------------------
#
# A glob sorts lexically, so 10000.sh comes before 9999.sh. Every migration
# name being the same width is the only reason the runner's order matches the
# numbers, and unix timestamps stay ten digits until well past any horizon
# worth planning for. Written down because the first draft of this suite used
# short fixtures and measured the wrong thing.
widths=$(for m in "$REPO/migrations"/*.sh; do basename "$m" .sh; done |
  awk '{ print length($0) }' | sort -u | tr '\n' ' ')
check "every migration name in the repository is the same width" "$widths" "10 "

newest=$(for m in "$REPO/migrations"/*.sh; do basename "$m" .sh; done |
  grep -E '^[0-9]+$' | sort -n | tail -1)
globbed=$(for m in "$REPO/migrations"/*.sh; do basename "$m" .sh; done | tail -1)
check "so the highest numbered migration is also the last one globbed" \
  "$globbed" "$newest"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
