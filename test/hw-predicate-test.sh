#!/bin/bash
# The hardware predicates answer by exit status and print nothing, so a caller
# can use one as a condition. Both answers of both predicates are exercised
# here without depending on what hardware this machine actually has, because a
# check that only ever sees one answer has only ever tested half of it.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"; mkdir -p "$STUB"

# lspci is a command, so a stub on PATH decides what the NVIDIA predicate sees.
with_nvidia() {
  cat >"$STUB/lspci" <<'STUBEOF'
#!/bin/bash
echo "00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [UHD Graphics]"
echo "01:00.0 VGA compatible controller: NVIDIA Corporation AD107M [GeForce RTX 4050]"
STUBEOF
  chmod +x "$STUB/lspci"
}
without_nvidia() {
  cat >"$STUB/lspci" <<'STUBEOF'
#!/bin/bash
echo "00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [UHD Graphics]"
STUBEOF
  chmod +x "$STUB/lspci"
}

with_nvidia
PATH="$STUB:$PATH" bash "$BIN/hyprsimple-hw-nvidia.sh"
check "nvidia predicate exits 0 when lspci reports one" "$?" "0"

out=$(PATH="$STUB:$PATH" bash "$BIN/hyprsimple-hw-nvidia.sh" 2>/dev/null)
check "nvidia predicate prints nothing when it says yes" "$out" ""

without_nvidia
PATH="$STUB:$PATH" bash "$BIN/hyprsimple-hw-nvidia.sh"
check "nvidia predicate exits non-zero when lspci reports none" "$?" "1"

out=$(PATH="$STUB:$PATH" bash "$BIN/hyprsimple-hw-nvidia.sh" 2>/dev/null)
check "nvidia predicate prints nothing when it says no" "$out" ""

# The battery predicate reads sysfs, which no PATH stub can replace, so it
# takes its root from the environment. That override exists for this test and
# is the only reason both answers are reachable on one machine.
mkdir -p "$TMP/power-with/BAT0" "$TMP/power-without/AC"

HYPRSIMPLE_SYSFS_POWER="$TMP/power-with" bash "$BIN/hyprsimple-hw-battery.sh"
check "battery predicate exits 0 when a BAT entry exists" "$?" "0"

out=$(HYPRSIMPLE_SYSFS_POWER="$TMP/power-with" bash "$BIN/hyprsimple-hw-battery.sh" 2>/dev/null)
check "battery predicate prints nothing when it says yes" "$out" ""

HYPRSIMPLE_SYSFS_POWER="$TMP/power-without" bash "$BIN/hyprsimple-hw-battery.sh"
check "battery predicate exits non-zero with no BAT entry" "$?" "1"

out=$(HYPRSIMPLE_SYSFS_POWER="$TMP/power-without" bash "$BIN/hyprsimple-hw-battery.sh" 2>/dev/null)
check "battery predicate prints nothing when it says no" "$out" ""

# The duplication this change exists to remove. One definition of the battery
# question, and no caller deciding NVIDIA presence by testing a captured string
# for emptiness. install.sh still runs lspci to read the model name, which the
# driver regexes need and a boolean cannot carry.
check "the battery question is asked in one place" \
  "$(grep -rl 'power_supply' "$BIN"/*.sh "$REPO/install.sh" | wc -l | tr -d ' ')" "1"
check "no caller answers the nvidia question from a captured string" \
  "$(grep -c 'if \[\[ -z \$NVIDIA \]\]' "$REPO/install.sh")" "0"
check "hw-intel-laptop defers to the battery predicate" \
  "$(grep -c 'hyprsimple-hw-battery.sh' "$BIN/hyprsimple-hw-intel-laptop.sh")" "1"

# install.sh populates ~/.local/bin at line 538, but calls setup_battery at
# 404. A predicate invoked from the home directory does not exist yet at that
# point, bash exits 127, and the `if` reads that as "no battery", which would
# set a performance power profile on a laptop. Calling the repo copy has no
# such ordering dependency, because install.sh runs from the repo.
check "install.sh calls predicates from the repo, not the home directory" \
  "$(grep -c 'bash "\$HOME/.local/bin/hyprsimple-hw-' "$REPO/install.sh")" "0"
check "install.sh calls all three predicates from DOTFILES_DIR" \
  "$(grep -c 'bash "\$DOTFILES_DIR/.local/bin/hyprsimple-hw-' "$REPO/install.sh")" "3"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
