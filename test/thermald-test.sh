#!/bin/bash
# install.sh installs and enables thermald on every Intel laptop, and a machine
# whose distribution already runs intel_lpmd for the same job, as CachyOS does
# through chwd, got a second thermal daemon beside the first. The block asks
# whether intel_lpmd is active and installs nothing when it is.
#
# The block is lifted out of install.sh by its first comment line and its
# closing fi, the way aur-helper-test.sh lifts the AUR block, and run with
# systemctl, sudo and pacman stubbed to a log. The Intel laptop predicate is a
# stub too, in a throwaway DOTFILES_DIR, so the answer is the suite's and not
# this machine's.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

BLOCK="$TMP/block.sh"
sed -n '/^install_packages() {/,/^}/p' "$REPO/install.sh" >"$BLOCK"
sed -n '/^# thermald is Intel-only/,/^fi$/p' "$REPO/install.sh" >>"$BLOCK"
for marker in 'install_packages() {' 'hyprsimple-hw-intel-laptop.sh' 'intel_lpmd' 'thermald'; do
  if grep -qF -- "$marker" "$BLOCK"; then
    pass "lifted source contains $marker"
  else
    fail "lifted source is missing $marker, so nothing below is testing install.sh"
  fi
done

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"
cat >"$STUB/systemctl" <<'STUBEOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALL_LOG"
case "$*" in
  *is-active*intel_lpmd*) [[ ${LPMD_ACTIVE:-no} == yes ]] && exit 0; exit 3 ;;
esac
exit 0
STUBEOF
cat >"$STUB/pacman" <<'STUBEOF'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$CALL_LOG"
exit 0
STUBEOF
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
"$@"
STUBEOF
chmod +x "$STUB"/*

# A throwaway tree whose predicate answers as told.
DOTFILES="$TMP/dotfiles"; mkdir -p "$DOTFILES/.local/bin"
printf '#!/bin/bash\n[[ ${INTEL_LAPTOP:-no} == yes ]]\n' >"$DOTFILES/.local/bin/hyprsimple-hw-intel-laptop.sh"

run_block() {
  : >"$LOG"
  INTEL_LAPTOP="$1" LPMD_ACTIVE="${2:-no}" CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" \
    DOTFILES_DIR="$DOTFILES" \
    bash -c '
      set -uo pipefail
      RED=""; GREEN=""; YELLOW=""; NC=""
      FAILED_PACKAGES=()
      source "'"$BLOCK"'"
    ' >"$TMP/out" 2>&1
}

# --- an Intel laptop where intel_lpmd already runs ---------------------------

run_block yes yes
check "with intel_lpmd active nothing is installed" "$(grep -c '^pacman -S' "$LOG")" "0"
check "and thermald is not enabled" "$(grep -c 'enable --now thermald' "$LOG")" "0"
check "and the output names intel_lpmd" "$(grep -c 'intel_lpmd' "$TMP/out")" "1"

# --- an Intel laptop without it ----------------------------------------------

run_block yes no
check "without intel_lpmd thermald is installed once" "$(grep -c '^pacman -S' "$LOG")" "1"
check "only if missing" "$(grep -c -- '--needed' "$LOG")" "1"
check "and enabled" "$(grep -c 'enable --now thermald' "$LOG")" "1"

# --- not an Intel laptop -----------------------------------------------------

run_block no
check "elsewhere nothing is installed" "$(grep -c '^pacman' "$LOG")" "0"
check "and nothing is enabled" "$(grep -c 'enable' "$LOG")" "0"
check "and the step says why" "$(grep -c 'not an Intel laptop' "$TMP/out")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
