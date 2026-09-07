#!/bin/bash
# The installer appended its environment blocks rather than replacing them.
#
# Three places wrote into ~/.config/uwsm with `cat >>`:
#
#   the Turing+ NVIDIA block          -> uwsm/env
#   the Maxwell/Pascal/Volta block    -> uwsm/env
#   the primary GPU block             -> uwsm/env-hyprland
#
# Right on a first install, wrong on every one after it. Re-running the
# installer is a documented step: the failed-packages message says to install
# the missing ones by hand and re-run, so a second run is expected. Two runs
# left the file holding
#
#   export AQ_DRM_DEVICES="/dev/dri/intel-gpu"
#   export AQ_DRM_DEVICES="/dev/dri/intel-gpu"
#
# and a block more on each run after that. uwsm reads the file once at login
# and the last export of a name wins, so nothing breaks visibly, which is
# exactly how it piles up unnoticed. theme-switcher.sh already replaces rather
# than appends for XCURSOR_THEME and says why.
#
# Nothing here runs the installer. set_env_block is taken out of it and run
# against throwaway files.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO/install.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

fn=$(sed -n '/^set_env_block() {/,/^}/p' "$INSTALL")
if [[ $(printf '%s\n' "$fn" | grep -c .) -lt 20 ]]; then
  fail "extracted $(printf '%s\n' "$fn" | grep -c .) lines of set_env_block, so this is reading the wrong thing"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "extracted set_env_block from the installer"

write_block() {
  bash -c "
    $fn
    set_env_block \"\$@\"
  " _ "$@"
}

F="$TMP/env"
count() { grep -c "$1" "$F"; }

# --- writing it twice leaves one copy -----------------------------------------

: >"$F"
write_block "$F" gpu "# Primary GPU: Intel" 'export AQ_DRM_DEVICES="/dev/dri/intel-gpu"'
check "the first write puts the export in" "$(count '^export AQ_DRM_DEVICES=')" "1"
check "and its comment" "$(count 'Primary GPU: Intel')" "1"

write_block "$F" gpu "# Primary GPU: Intel" 'export AQ_DRM_DEVICES="/dev/dri/intel-gpu"'
write_block "$F" gpu "# Primary GPU: Intel" 'export AQ_DRM_DEVICES="/dev/dri/intel-gpu"'
check "and two more writes still leave one" "$(count '^export AQ_DRM_DEVICES=')" "1"
check "with one comment, not three" "$(count 'Primary GPU: Intel')" "1"

# --- a changed value replaces the old one, rather than sitting under it -------

write_block "$F" gpu "# Primary GPU: AMD" 'export AQ_DRM_DEVICES="/dev/dri/amd-gpu"'
check "a rewritten block holds the new value" "$(count 'amd-gpu')" "1"
check "and the old value is gone, not shadowed" "$(count 'intel-gpu')" "0"

# --- what the user put there is kept ------------------------------------------

printf 'export MY_OWN=1\n# my note\n' >"$F"
write_block "$F" gpu "# Primary GPU: Intel" 'export AQ_DRM_DEVICES="/dev/dri/intel-gpu"'
write_block "$F" gpu "# Primary GPU: Intel" 'export AQ_DRM_DEVICES="/dev/dri/intel-gpu"'
check "an unrelated export of the user's survives" "$(count '^export MY_OWN=1$')" "1"
check "and their comment" "$(count '^# my note$')" "1"

# --- a block written before the markers existed is cleaned up -----------------
#
# Without this a second install would leave the old copy sitting above the new
# one, which is the thing being fixed.

printf '\n# NVIDIA - auto-detected by installer\nexport NVD_BACKEND=direct\nexport LIBVA_DRIVER_NAME=nvidia\n' >"$F"
check "the legacy fixture really has the export" "$(count '^export NVD_BACKEND=')" "1"
write_block "$F" nvidia "# NVIDIA - auto-detected by installer" \
  'export NVD_BACKEND=direct' 'export LIBVA_DRIVER_NAME=nvidia'
check "an unmarked copy from an older install is removed" \
  "$(count '^export NVD_BACKEND=')" "1"
check "and so is its second export" "$(count '^export LIBVA_DRIVER_NAME=')" "1"

# --- two different blocks live side by side -----------------------------------

: >"$F"
write_block "$F" nvidia "# NVIDIA" 'export NVD_BACKEND=direct'
write_block "$F" gpu "# GPU" 'export AQ_DRM_DEVICES="/dev/dri/intel-gpu"'
write_block "$F" nvidia "# NVIDIA" 'export NVD_BACKEND=direct'
check "rewriting one block leaves the other alone" \
  "$(count '^export AQ_DRM_DEVICES=')" "1"
check "and does not duplicate itself" "$(count '^export NVD_BACKEND=')" "1"

# --- the file is still something a shell can read -----------------------------

check "the result parses as shell" \
  "$(bash -n "$F" 2>&1 && echo ok)" "ok"

# --- and the installer uses it everywhere -------------------------------------

code_of() { sed 's/#.*//' "$1"; }
CODE="$TMP/install.code"
code_of "$INSTALL" >"$CODE"
check "stripping comments leaves the installer's code behind" \
  "$(grep -c '^set_env_block()' "$CODE")" "1"
check "all three blocks go through it" \
  "$(grep -c '^ *set_env_block "' "$CODE")" "3"
check "and nothing appends into a home config any more" \
  "$(grep -cE '>>[[:space:]]*"?\$HOME' "$CODE")" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
