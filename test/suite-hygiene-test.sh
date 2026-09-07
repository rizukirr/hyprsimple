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

# A suite must not touch the state a shipped script keeps on the real machine.
#
# Two of them ran battery-monitor.sh against its real /tmp paths. Running the
# tests deleted the live notification flag out from under the running service,
# so the next tick notified and dimmed again, and left a brightness record of
# 500 behind, which the next charge would have restored the screen to. Both
# were found on the maintainer's own machine, by a file reappearing after it
# was deleted.
#
# The paths are read out of the script rather than listed here. A list written
# down in this file would keep passing after the script renamed its paths,
# which is the shape of failure this whole suite exists to catch.
monitor="$REPO/.local/bin/battery-monitor.sh"
mapfile -t state_paths < <(
  grep -oE '\$\{HYPRSIMPLE_[A-Z_]+:-[^}]+\}' "$monitor" |
    sed 's/.*:-//; s/}$//' |
    LC_ALL=C sort -u
)
mapfile -t state_vars < <(
  grep -oE 'HYPRSIMPLE_[A-Z_]+' "$monitor" | LC_ALL=C sort -u
)

if [[ ${#state_paths[@]} -lt 2 || ${#state_vars[@]} -lt 2 ]]; then
  fail "read ${#state_paths[@]} state paths and ${#state_vars[@]} overrides out of battery-monitor.sh, so this check is not reading it"
else
  pass "read ${#state_paths[@]} overridable state paths out of battery-monitor.sh"

  named=()
  unisolated=()
  runners=()
  for suite in "${suites[@]}"; do
    for path in "${state_paths[@]}"; do
      grep -qF -- "$path" "$suite" && named+=("$(basename "$suite"):$path")
    done
    # Comments stripped, and matching an invocation rather than the name.
    # Two suites name the script only to explain something and one names
    # battery-monitor.service throughout, and counting those made this read as
    # a failure in files that never run it.
    #
    # Every invocation is checked, not the file as a whole. The first version
    # asked whether the suite mentioned the overrides anywhere, and a suite
    # that isolated two of its three runs passed while the third wrote to the
    # real paths. Continuations are joined first, so the environment in front
    # of the command is on the same line as the command.
    while IFS= read -r invocation; do
      runners+=("$(basename "$suite")")
      for var in "${state_vars[@]}"; do
        [[ $invocation == *"$var"* ]] ||
          unisolated+=("$(basename "$suite") runs it without $var")
      done
    done < <(
      sed 's/#.*//' "$suite" |
        sed -e :a -e '/\\$/N; s/\\\n//; ta' |
        grep -E 'bash [^|;&]*battery-monitor\.sh'
    )
  done

  # Or the loop above would report nothing wrong by never reaching a run.
  # A floor, not the current count. Pinning the exact number would fail the
  # day a suite gained or dropped a run, which says nothing about isolation.
  if (( ${#runners[@]} < 2 )); then
    fail "found ${#runners[@]} runs of battery-monitor.sh in the suites, so the isolation check is reading none of them"
  else
    pass "found ${#runners[@]} runs of battery-monitor.sh across the suites"
  fi

  named_str=""
  (( ${#named[@]} > 0 )) && named_str="$(printf '%s ' "${named[@]}")"
  check "no suite names a real state path of a shipped script" "$named_str" ""

  unisolated_str=""
  (( ${#unisolated[@]} > 0 )) && unisolated_str="$(printf '%s; ' "${unisolated[@]}")"
  check "and every suite running battery-monitor.sh overrides all of them" \
    "$unisolated_str" ""
fi

# A suite must not be able to reach the real rofi.
#
# rofi opens a window on whoever is running the tests. Several of these suites
# run scripts that open a picker when given no argument, with /usr/bin on the
# PATH they build, and had no rofi of their own in front of it. That is not
# theoretical: during one sabotage run a picker was reached and rofi appeared on
# the maintainer's screen, complaining about a theme path inside the fixture.
#
# The scripts that can open one are read out of the repository rather than
# listed here, so a picker added to another script later is covered without
# this check being touched.
mapfile -t picker_scripts < <(
  for script in "$REPO/.local/bin"/*.sh; do
    sed 's/#.*//' "$script" | grep -q 'hyprsimple-image-picker.sh' &&
      basename "$script"
  done
)
# hyprsimple-image-picker.sh is the one that actually runs rofi, so it counts
# too.
picker_scripts+=(hyprsimple-image-picker.sh)

if (( ${#picker_scripts[@]} < 3 )); then
  fail "found ${#picker_scripts[@]} scripts that can open a picker, which is too few to be right"
else
  pass "found ${#picker_scripts[@]} scripts that can open a picker"
fi

unstubbed=()
for suite in "${suites[@]}"; do
  # Whole-line comments only. Stripping from the first # anywhere cut
  # `printf '#!/bin/bash\n...' >"$STUB/rofi"` down to `printf '`, so the stub
  # this check is looking for disappeared and three suites that have one were
  # reported as missing it.
  code=$(sed 's/^[[:space:]]*#.*//' "$suite")
  # Only suites that put a directory of their own ahead of a real one.
  grep -q 'PATH="\$STUB:' <<<"$code" || continue
  runs_picker=0
  for script in "${picker_scripts[@]}"; do
    grep -qF "$script" <<<"$code" && runs_picker=1
  done
  (( runs_picker )) || continue
  grep -q 'rofi' <<<"$code" || unstubbed+=("$(basename "$suite")")
done

unstubbed_str=""
(( ${#unstubbed[@]} > 0 )) && unstubbed_str="$(printf '%s ' "${unstubbed[@]}")"
check "every suite that can reach rofi puts one of its own in front of it" \
  "$unstubbed_str" ""

# The same for notify-send, and for the same reason.
#
# A notification from a test lands on the desktop of whoever is running it.
# theme-switcher.sh gained a warning for a cursor theme that is not installed,
# cursor-theme-test.sh drives exactly that case, and the warning reached the
# maintainer's screen because that suite stubbed gsettings and hyprctl and not
# notify-send.
#
# The scripts that notify are read out of the repository, so one that starts
# notifying later is covered without this check being touched.
mapfile -t notifying < <(
  for script in "$REPO/.local/bin"/*.sh; do
    sed 's/^[[:space:]]*#.*//' "$script" | grep -q 'notify-send' &&
      basename "$script"
  done
)

if (( ${#notifying[@]} < 5 )); then
  fail "found ${#notifying[@]} scripts that notify, which is too few to be right"
else
  pass "found ${#notifying[@]} scripts that send notifications"
fi

noisy=()
for suite in "${suites[@]}"; do
  code=$(sed 's/^[[:space:]]*#.*//' "$suite")
  grep -q 'PATH="\$STUB:' <<<"$code" || continue
  runs_notifier=0
  for script in "${notifying[@]}"; do
    grep -qE "bash [^|;&]*$script" <<<"$code" && runs_notifier=1
  done
  (( runs_notifier )) || continue
  grep -q 'notify-send' <<<"$code" || noisy+=("$(basename "$suite")")
done

noisy_str=""
(( ${#noisy[@]} > 0 )) && noisy_str="$(printf '%s ' "${noisy[@]}")"
check "every suite that runs a notifying script stubs notify-send" "$noisy_str" ""

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
