#!/bin/bash
# hyprsimple installed a browser and ffmpeg and no VA-API driver for Intel, so
# on an Intel laptop video was decoded on the CPU. That includes every hybrid
# laptop, because there the desktop runs on the integrated GPU.
#
# Measured on an Intel laptop with intel-media-driver in place:
#
#   Brave, started with no flags    71.6 s on the Intel video engine, read from
#                                   drm-engine-video in its GPU process's fdinfo
#   LIBVA_DRIVER_NAME unset         libva opened iHD_drv_video.so by itself
#   the driver files hidden         libva tried iHD, then i965, then gave up
#
# The last row is a hyprsimple install before this, and it is also why both
# drivers are installed: libva does the choosing between them, so nothing here
# has to tell one GPU generation from another.
#
# install.sh installs them on a fresh machine and a migration on one already
# installed. Both are driven here against stubs. Nothing installs anything, and
# pacman, sudo and lspci are never the real ones.

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

# Take the functions out of install.sh by name. install.sh cannot be sourced:
# it installs a desktop from the top of the file down.
FUNCS="$TMP/funcs.sh"
sed -n '/^detect_and_install_intel_video() {/,/^}/p' "$REPO/install.sh" >"$FUNCS"
sed -n '/^install_packages() {/,/^}/p' "$REPO/install.sh" >>"$FUNCS"

# An extraction that produced nothing would let every "pacman is not called"
# check below pass for the wrong reason.
for marker in 'detect_and_install_intel_video() {' 'install_packages() {' \
  'intel-media-driver' 'libva-intel-driver'; do
  if grep -qF -- "$marker" "$FUNCS"; then
    pass "extracted source contains $marker"
  else
    fail "extracted source is missing $marker, so nothing below is testing install.sh"
  fi
done

# Found by looking rather than named, so the suite follows the file if the
# migration is ever renamed.
MIGRATION="$(grep -lF 'Install the Intel video decode drivers' "$REPO"/migrations/*.sh | head -1)"
if [[ -n $MIGRATION ]]; then
  pass "the migration exists"
else
  fail "no migration installs the Intel video decode drivers, so nothing below is testing one"
  MIGRATION="$TMP/missing-migration.sh"
fi

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"

# GPUS says what this machine has, one word per controller.
cat >"$STUB/lspci" <<'STUBEOF'
#!/bin/bash
for gpu in ${GPUS:-}; do
  case "$gpu" in
    intel-vga)     printf '00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [UHD Graphics]\n' ;;
    intel-display) printf '00:02.0 Display controller: Intel Corporation Alder Lake-P GT2 [Iris Xe Graphics]\n' ;;
    nvidia)        printf '01:00.0 VGA compatible controller: NVIDIA Corporation AD107M [GeForce RTX 4050 Max-Q / Mobile]\n' ;;
    amd)           printf '05:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Rembrandt\n' ;;
  esac
done
printf '00:1f.3 Audio device: Intel Corporation Raptor Lake-P/U/H cAVS\n'
STUBEOF

# INSTALLED lists what pacman should report as present, and PACMAN_RC is how an
# install ends. A successful install is not recorded as installed: the test
# says what is on the machine, the stub does not decide.
cat >"$STUB/pacman" <<'STUBEOF'
#!/bin/bash
case "${1:-}" in
  -Qq) [[ " ${INSTALLED:-} " == *" $2 "* ]] && exit 0; exit 1 ;;
esac
printf 'pacman %s\n' "$*" >>"$CALL_LOG"
exit "${PACMAN_RC:-0}"
STUBEOF

cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
"$@"
STUBEOF
chmod +x "$STUB"/*

# The audio line is there on purpose. Every Intel machine has Intel devices
# that are not GPUs, and a pattern that matched "Intel" anywhere would install
# video drivers on an AMD laptop with an Intel wifi card.

rc=0
run_install() {
  : >"$LOG"
  GPUS="$1" INSTALLED="${2:-}" PACMAN_RC="${3:-0}" CALL_LOG="$LOG" \
    PATH="$STUB:/usr/bin:/bin" \
    bash -c '
      set -uo pipefail
      RED=""; GREEN=""; YELLOW=""; NC=""
      FAILED_PACKAGES=()
      source "'"$FUNCS"'"
      detect_and_install_intel_video
      status=$?
      printf "FAILED=%s\n" "${FAILED_PACKAGES[*]}"
      exit "$status"
    ' >"$TMP/out" 2>&1
  rc=$?
}
installs() { grep -c '^pacman -S ' "$LOG"; }

# --- install.sh, on a machine with an Intel GPU ------------------------------

for gpus in "intel-vga" "intel-display" "intel-vga nvidia"; do
  run_install "$gpus"
  check "[$gpus] pacman is asked for the drivers once" "$(installs)" "1"
  check "[$gpus] for intel-media-driver" "$(grep -c 'intel-media-driver' "$LOG")" "1"
  check "[$gpus] and for libva-intel-driver" "$(grep -c 'libva-intel-driver' "$LOG")" "1"
  check "[$gpus] without stopping to ask" "$(grep -c -- '--noconfirm' "$LOG")" "1"
  check "[$gpus] and the step returns 0" "$rc" "0"
done

# --- and on one without ------------------------------------------------------

for gpus in "amd" "nvidia" ""; do
  run_install "$gpus"
  check "[${gpus:-no GPU}] pacman is not called" "$(installs)" "0"
  check "[${gpus:-no GPU}] and the step says it found no Intel GPU" \
    "$(grep -c 'No Intel GPU detected' "$TMP/out")" "1"
  check "[${gpus:-no GPU}] and returns 0" "$rc" "0"
done

# --- a failed install does not stop the installer ----------------------------

run_install "intel-vga" "" 1
check "with pacman failing the step still returns 0" "$rc" "0"
check "and both packages are recorded as failed" \
  "$(grep '^FAILED=' "$TMP/out")" "FAILED=intel-media-driver libva-intel-driver"
check "and it says video will be decoded on the CPU" \
  "$(grep -c 'decoded on the CPU' "$TMP/out")" "1"
check "and does not say a driver was installed" \
  "$(grep -c 'driver installed' "$TMP/out")" "0"

run_install "intel-vga" "intel-media-driver libva-intel-driver"
check "with the drivers present it says video is decoded on the GPU" \
  "$(grep -c 'decoded on the GPU' "$TMP/out")" "1"

# --- the installer actually runs the step ------------------------------------

check "install.sh calls the step once" \
  "$(grep -c '^detect_and_install_intel_video || true$' "$REPO/install.sh")" "1"
check "right after the Vulkan step, with the other hardware steps" \
  "$(grep -A1 '^detect_and_install_vulkan || true$' "$REPO/install.sh" | tail -1)" \
  "detect_and_install_intel_video || true"

# --- the migration, for machines already installed ---------------------------

run_migration() {
  : >"$LOG"
  GPUS="$1" INSTALLED="${2:-}" PACMAN_RC="${3:-0}" CALL_LOG="$LOG" \
    PATH="$STUB:/usr/bin:/bin" \
    bash "$MIGRATION" >"$TMP/out" 2>&1
  rc=$?
}

run_migration "intel-vga"
check "with neither driver installed the migration installs once" "$(installs)" "1"
check "both of them, only if needed, and without asking" \
  "$(cat "$LOG")" "pacman -S --needed --noconfirm intel-media-driver libva-intel-driver"
check "and exits 0" "$rc" "0"
check "and says the browser has to be restarted" "$(grep -c 'Restart your browser' "$TMP/out")" "1"

run_migration "intel-vga" "intel-media-driver"
check "with one driver installed it asks only for the other" \
  "$(cat "$LOG")" "pacman -S --needed --noconfirm libva-intel-driver"

run_migration "intel-display nvidia" "libva-intel-driver"
check "whichever one that is" \
  "$(cat "$LOG")" "pacman -S --needed --noconfirm intel-media-driver"

run_migration "intel-vga" "intel-media-driver libva-intel-driver"
check "with both installed it installs nothing" "$(installs)" "0"
check "and exits 0" "$rc" "0"

for gpus in "amd" "nvidia"; do
  run_migration "$gpus"
  check "[$gpus] with no Intel GPU the migration installs nothing" "$(installs)" "0"
  check "[$gpus] and exits 0" "$rc" "0"
done

# The runner offers to retry or skip a migration that fails, and it can only
# do that if the failure reaches it.
run_migration "intel-vga" "" 1
check "a failed install exits non-zero, so the runner sees it" "$rc" "1"
check "and does not claim anything was installed" "$(grep -c 'Installed' "$TMP/out")" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
