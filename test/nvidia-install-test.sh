#!/bin/bash
# detect_and_install_nvidia had never been run by anything, and it installed
# the legacy driver with the wrong package manager.
#
# The Maxwell/Pascal/Volta branch installs nvidia-580xx-dkms, nvidia-580xx-utils
# and lib32-nvidia-580xx-utils. None of the three is in any official Arch
# repository, and all three were passed to `sudo pacman -S`, so on stock Arch
# every GTX 9xx and 10xx machine got three "target not found" failures. That
# was survivable. What followed was not: install_packages records failures and
# returns 0 regardless, so the function went on to append
# __GLX_VENDOR_LIBRARY_NAME=nvidia to uwsm/env, rebuild the initramfs, and
# print "NVIDIA setup complete". That variable points GLX at libGLX_nvidia.so.0
# and, with no driver installed, every OpenGL application in the next session
# fails. The installer's own advice is to re-run it, which reproduced the same
# state.
#
# Both branches are driven here, both with the install working and with it
# failing, against stubs. Nothing installs anything.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# Take the function out of install.sh by name. install.sh cannot be sourced:
# it installs a desktop from the top of the file down.
FUNCS="$TMP/funcs.sh"
sed -n '/^detect_and_install_nvidia() {/,/^}/p' "$REPO/install.sh" >"$FUNCS"
sed -n '/^install_packages() {/,/^}/p' "$REPO/install.sh" >>"$FUNCS"

# An extraction that quietly produced nothing would let every check below pass
# for the wrong reason. This is the shape that has already cost this repository
# five vacuous checks, so assert the extraction before using it.
for marker in 'detect_and_install_nvidia() {' 'install_packages() {' \
  'NVIDIA_UTILS_PKG' 'nvidia-580xx-dkms' '__GLX_VENDOR_LIBRARY_NAME'; do
  if grep -qF -- "$marker" "$FUNCS"; then
    pass "extracted source contains $marker"
  else
    fail "extracted source is missing $marker, so nothing below is testing install.sh"
  fi
done

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"

cat >"$STUB/lspci" <<'STUBEOF'
#!/bin/bash
printf '00:02.0 VGA compatible controller: Intel Corporation UHD Graphics\n'
printf '01:00.0 VGA compatible controller: NVIDIA Corporation %s\n' "$NVIDIA_MODEL"
STUBEOF

# INSTALLED lists the packages pacman should claim are present, so the test
# says whether the driver landed rather than the stub deciding.
cat >"$STUB/pacman" <<'STUBEOF'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$CALL_LOG"
case "${1:-}" in
  -Si) [[ " ${REPO_PACKAGES:-} " == *" $2 "* ]] && exit 0; exit 1 ;;
  -Qq) [[ " ${INSTALLED:-} " == *" $2 "* ]] && exit 0; exit 1 ;;
esac
exit 0
STUBEOF

# sudo runs what follows it, so `sudo pacman` reaches the pacman stub.
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
"$@"
STUBEOF

# The two installers a driver site can be handed. Each logs and reports whether
# the test wants it to succeed.
for helper in paru mkinitcpio; do
  cat >"$STUB/$helper" <<STUBEOF
#!/bin/bash
printf '$helper %s\n' "\$*" >>"\$CALL_LOG"
exit "\${INSTALL_RC:-0}"
STUBEOF
done
chmod +x "$STUB"/*

# A kernel whose pkgbase is known, so KERNEL_HEADERS is derived rather than
# skipped. Without this the function returns early on any CI runner.
MODULES="$TMP/modules/$(uname -r)"
mkdir -p "$MODULES"
printf 'linux\n' >"$MODULES/pkgbase"

HOME_DIR="$TMP/home"

# Run the function with one scenario's worth of environment.
run_nvidia() {
  rm -rf "$HOME_DIR"; mkdir -p "$HOME_DIR/.config/uwsm"
  : >"$LOG"
  HOME="$HOME_DIR" CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" \
    HYPRSIMPLE_MODULES_DIR="$TMP/modules" \
    NVIDIA_MODEL="$1" INSTALLED="$2" INSTALL_RC="${3:-0}" \
    REPO_PACKAGES="${4:-}" \
    bash -c '
      set -uo pipefail
      RED=""; GREEN=""; YELLOW=""; NC=""
      AUR_HELPER="paru"
      DOTFILES_DIR="'"$REPO"'"
      FAILED_PACKAGES=()
      source "'"$FUNCS"'"
      detect_and_install_nvidia
    ' >"$TMP/out" 2>&1
}

env_file() { cat "$HOME_DIR/.config/uwsm/env" 2>/dev/null; }

# --- the legacy branch reaches the AUR helper, not pacman -------------------

run_nvidia "GP106 [GeForce GTX 1060 6GB]" "nvidia-580xx-utils"
check "a GTX 1060 is recognised as the legacy generation" \
  "$(grep -c 'nvidia-580xx-dkms' "$LOG")" "1"
check "and the legacy driver is installed with the AUR helper" \
  "$(grep -c '^paru .*nvidia-580xx-dkms' "$LOG")" "1"
check "and not with pacman, which cannot resolve those names" \
  "$(grep -c '^pacman -S .*nvidia-580xx' "$LOG")" "0"

# --- a failed install must not write the env vars ---------------------------

run_nvidia "GP106 [GeForce GTX 1060 6GB]" "" 1
check "with the legacy driver missing no GLX vendor is exported" \
  "$(env_file | grep -c '__GLX_VENDOR_LIBRARY_NAME')" "0"
check "and the initramfs is not rebuilt" "$(grep -c '^mkinitcpio' "$LOG")" "0"
check "and the failure is named" \
  "$(grep -c 'nvidia-580xx-utils is not installed' "$TMP/out")" "1"
check "and it does not claim the setup completed" \
  "$(grep -c 'NVIDIA setup complete' "$TMP/out")" "0"

run_nvidia "AD107M [GeForce RTX 4050 Max-Q]" "" 1
check "with the current driver missing no GLX vendor is exported either" \
  "$(env_file | grep -c '__GLX_VENDOR_LIBRARY_NAME')" "0"
check "and that failure names the current utils package" \
  "$(grep -c 'nvidia-utils is not installed' "$TMP/out")" "1"

# --- a successful install still writes the right block ----------------------

run_nvidia "AD107M [GeForce RTX 4050 Max-Q]" "nvidia-utils"
check "a working Turing+ install exports the direct backend" \
  "$(env_file | grep -c 'NVD_BACKEND=direct')" "1"
check "and rebuilds the initramfs" "$(grep -c '^mkinitcpio -P' "$LOG")" "1"
check "and reports the architecture it chose" \
  "$(grep -c 'arch: turing_plus' "$TMP/out")" "1"
check "and Turing+ still goes through pacman" \
  "$(grep -c '^pacman -S .*nvidia-open-dkms' "$LOG")" "1"

run_nvidia "GP106 [GeForce GTX 1060 6GB]" "nvidia-580xx-utils"
check "a working legacy install exports the egl backend" \
  "$(env_file | grep -c 'NVD_BACKEND=egl')" "1"
check "and never exports the direct backend" \
  "$(env_file | grep -c 'NVD_BACKEND=direct')" "0"

# A derivative that ships a prebuilt module for this kernel must be preferred
# over the DKMS build.
run_nvidia "AD107M [GeForce RTX 4050 Max-Q]" "nvidia-utils" 0 "linux-nvidia-open"
check "a prebuilt kernel module is preferred over DKMS" \
  "$(grep -c '^pacman -S .*linux-nvidia-open' "$LOG")" "1"
check "and DKMS is then not installed" \
  "$(grep -c 'nvidia-open-dkms' "$LOG")" "0"

# --- no NVIDIA at all -------------------------------------------------------

cat >"$STUB/lspci" <<'STUBEOF'
#!/bin/bash
printf '00:02.0 VGA compatible controller: Intel Corporation UHD Graphics\n'
STUBEOF
chmod +x "$STUB/lspci"
run_nvidia "" ""
check "a machine with no NVIDIA GPU installs nothing" \
  "$(grep -c 'nvidia' "$LOG")" "0"
check "and says so" "$(grep -c 'No NVIDIA GPU detected' "$TMP/out")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
