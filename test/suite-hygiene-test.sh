#!/bin/bash
# Checks the test suites themselves.
#
# Five checks in this repository have passed while testing nothing. Every one
# came from a fixture that resembled the real thing without being it: a suite
# reading the maintainer's real ~/.config, a clone that silently produced an
# empty directory, and two suites reconstructing fixtures from git history on a
# shallow CI checkout. Sabotage testing catches broken code, and caught none of
# these, because the code was fine and the fixture was not.
#
# These are the invariants that would have caught them, enforced mechanically.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SELF="$(basename "${BASH_SOURCE[0]}")"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# set -e is not on here, so calling a helper that does not exist prints
# "command not found" and carries on, and the suite still ends with "all checks
# passed". That happened while this file was being edited: five calls to check
# ran before check existed, and the run reported success.
#
# An ERR trap was the first attempt and was worse than nothing. This suite uses
# `grep -c` inside command substitutions, and grep exits 1 when a count is zero,
# so the trap fired on an ordinary result and reported a failure that had not
# happened. A guard that cries wolf on correct code trains people to ignore it.
#
# Naming the helpers instead. It catches the case that actually occurred and
# cannot misfire on an exit status.
for helper in pass fail check; do
  if ! declare -F "$helper" >/dev/null; then
    printf 'not ok - helper %s is not defined, so calls to it would pass silently\n' \
      "$helper" >&2
    exit 1
  fi
done

suites=()
while IFS= read -r f; do
  [[ $(basename "$f") == "$SELF" ]] && continue
  suites+=("$f")
done < <(find "$REPO/test" -maxdepth 1 -name '*.sh' | sort)

# The audit is worthless if it found nothing to audit.
if [[ ${#suites[@]} -lt 5 ]]; then
  fail "found ${#suites[@]} suites to audit, which is too few to be right"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "found ${#suites[@]} suites to audit"

# CI checks out shallow, and the workflow says so. On a depth-1 clone
# `git log --format=%H -- <path> | tail -1` resolves to HEAD, so a suite asking
# for an old version is handed the current one. That failed loudly in one suite
# and silently in another, where the migration checks compared a file against
# itself and passed.

# Comments are stripped first. Explaining this trap in a comment must not be
# what trips it.
code_of() { sed 's/#.*//' "$1"; }

offenders=()
for f in "${suites[@]}"; do
  code_of "$f" | grep -qE 'git .*(log|show|rev-list|ls-tree)' && offenders+=("$(basename "$f")")
done
if [[ ${#offenders[@]} -eq 0 ]]; then
  pass "no suite reconstructs fixtures from git history"
else
  fail "these read git history, which is empty on CI's shallow checkout: ${offenders[*]}"
fi

offenders=()
for f in "${suites[@]}"; do
  grep -q 'mktemp -d' "$f" || continue
  grep -q "trap 'rm -rf" "$f" || offenders+=("$(basename "$f")")
done
if [[ ${#offenders[@]} -eq 0 ]]; then
  pass "every suite that makes a temp directory removes it"
else
  fail "these leak their temp directory: ${offenders[*]}"
fi

# must_be_fixture stops an empty or unexpected path turning a later rm or cp
# into an operation on the real home directory. Defining it and never calling it
# looks like protection in a diff and provides none, which is a mistake made
# while writing this very suite.

offenders=()
for f in "${suites[@]}"; do
  code_of "$f" | grep -q 'must_be_fixture()' || continue
  calls=$(code_of "$f" | grep -cE '^\s*must_be_fixture "')
  [[ $calls -ge 1 ]] || offenders+=("$(basename "$f")")
done
if [[ ${#offenders[@]} -eq 0 ]]; then
  pass "every suite defining a fixture guard also calls it"
else
  fail "these define a fixture guard and never call it: ${offenders[*]}"
fi

# rofi resolves a relative @import against the XDG config directory before the
# working directory, so a fixture's imports silently resolved against the
# maintainer's real ~/.config/rofi and the checks passed for the wrong reason.

offenders=()
for f in "${suites[@]}"; do
  # An actual invocation, which always carries a flag. Prose about rofi and a
  # path ending in /rofi are not invocations.
  code_of "$f" | grep -qE '(^|[^-a-zA-Z/])rofi +-' || continue
  grep -q 'XDG_CONFIG_HOME' "$f" || offenders+=("$(basename "$f")")
done
if [[ ${#offenders[@]} -eq 0 ]]; then
  pass "every suite that runs rofi isolates XDG_CONFIG_HOME"
else
  fail "these run rofi without isolating the config directory: ${offenders[*]}"
fi

# The narrowest check in this suite, and the one that cost the most. A clone
# that produced nothing left four checks reporting ok, because each asserted on
# absence and an empty fixture produces no output either.

offenders=()
for f in "${suites[@]}"; do
  code_of "$f" | grep -qE 'git clone' || continue
  grep -qE 'did not clone|not ok - fixture' "$f" || offenders+=("$(basename "$f")")
done
if [[ ${#offenders[@]} -eq 0 ]]; then
  pass "every suite that clones asserts the clone produced something"
else
  fail "these clone without asserting the result exists: ${offenders[*]}"
fi

# The workflow names each suite explicitly, so a file that is not listed never
# runs there however good it is.

WORKFLOW="$REPO/.github/workflows/tests.yml"
offenders=()
for f in "${suites[@]}"; do
  grep -q "test/$(basename "$f")" "$WORKFLOW" || offenders+=("$(basename "$f")")
done
if [[ ${#offenders[@]} -eq 0 ]]; then
  pass "every suite is listed in the workflow"
else
  fail "these never run in CI: ${offenders[*]}"
fi

# AGENTS.md is the file a contributor reads before touching anything, so a
# claim in it that has quietly stopped being true costs more than the same
# claim anywhere else.
#
# It said install.sh:437 copies .local/bin to the user's home. Line 437 is a
# section comment, and the copy loop is at 671. A line number in prose is wrong
# as soon as anything above it moves and nothing announces that, so the rule is
# that this file cites code rather than positions, and the cited code is
# checked to still exist.

AGENTS="$REPO/AGENTS.md"

if [[ ! -f $AGENTS ]]; then
  fail "AGENTS.md is missing, and it is what a contributor reads first"
else
  numbered=$(grep -cE '`[A-Za-z0-9_./-]+\.(sh|lua|conf|yml|jsonc|rasi|md)?:[0-9]+`' "$AGENTS")
  check "AGENTS.md cites no line numbers, which cannot be kept true" "$numbered" "0"

  # Every backticked run of code in AGENTS.md that looks like a shell fragment
  # rather than a bare filename has to appear in the file it describes. Only
  # the install.sh anchor qualifies today, and naming it explicitly beats a
  # clever extractor that silently matches nothing.
  anchor='for script in "$DOTFILES_DIR/.local/bin"'
  check "AGENTS.md quotes the copy loop rather than pointing at a line" \
    "$(grep -cF "$anchor" "$AGENTS")" "1"
  check "and that line is still in install.sh, where it says it is" \
    "$(grep -cF "$anchor" "$REPO/install.sh")" "1"

  # Every repository path AGENTS.md names has to exist.
  #
  # Read out of the file rather than listed here. The first version of this
  # check held its own list and skipped any entry AGENTS.md did not mention, so
  # renaming a path in the document made the check quietly stop looking at it,
  # which is the failure mode this whole change is about.
  #
  # Paths beginning with ~ or $ describe the user's machine, not this
  # repository, and are not ours to verify.
  mapfile -t cited < <(
    grep -oE '`[^`]+`' "$AGENTS" |
      tr -d '`' |
      grep -E '^[A-Za-z0-9_.][A-Za-z0-9_./-]*/[A-Za-z0-9_./-]+$|^[A-Za-z0-9_-]+\.(sh|md|yml)$' |
      LC_ALL=C sort -u
  )
  if (( ${#cited[@]} < 3 )); then
    fail "found only ${#cited[@]} paths cited in AGENTS.md, so this check is not reading it"
  else
    pass "checked ${#cited[@]} repository paths cited in AGENTS.md"
  fi
  absent=()
  for path in "${cited[@]}"; do
    [[ -e $REPO/$path ]] || absent+=("$path")
  done
  absent_str=""
  (( ${#absent[@]} > 0 )) && absent_str="$(printf '%s ' "${absent[@]}")"
  check "and every one of them exists" "$absent_str" ""
fi

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
