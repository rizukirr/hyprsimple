#!/bin/bash
# install.sh appended this to ~/.config/uwsm/env on any machine with an NVIDIA
# GPU, without asking whether that GPU drives the desktop:
#
#   export NVD_BACKEND=direct
#   export LIBVA_DRIVER_NAME=nvidia
#   export __GLX_VENDOR_LIBRARY_NAME=nvidia
#
# On a hybrid laptop it does not drive the desktop. detect_and_setup_multi_gpu
# prefers Intel, then AMD, then NVIDIA, and points AQ_DRM_DEVICES at what it
# picks, so Hyprland renders on the integrated GPU. Those variables then send
# every OpenGL application to the discrete card, whose frames have to be copied
# back to the GPU that owns the display, and which never powers down.
#
# Measured on an Optimus laptop, inside the running session's own environment:
#
#   with the block     OpenGL renderer string: NVIDIA GeForce RTX 4050 Laptop GPU
#   with it unset      OpenGL renderer string: Mesa Intel(R) Graphics (RPL-P)
#
# Upstream writes the same block and has no equivalent of
# detect_and_setup_multi_gpu, so there it is consistent. hyprsimple added the
# GPU selection and left this half alone, and the two contradicted each other.
#
# A desktop whose only card is NVIDIA still needs the block and keeps it. Both
# answers are exercised here.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788623900.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

FUNCS="$TMP/funcs.sh"
sed -n '/^detect_and_install_nvidia() {/,/^}/p' "$REPO/install.sh" >"$FUNCS"
sed -n '/^install_packages() {/,/^}/p' "$REPO/install.sh" >>"$FUNCS"
for marker in 'detect_and_install_nvidia() {' 'other_gpu' '__GLX_VENDOR_LIBRARY_NAME'; do
  if grep -qF -- "$marker" "$FUNCS"; then
    pass "extracted source contains $marker"
  else
    fail "extracted source is missing $marker, so nothing below is testing install.sh"
  fi
done

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"

# lspci answers with whichever machine the test is describing. Both the plain
# and the -d ::0300 form have to be handled, because install.sh uses both.
cat >"$STUB/lspci" <<'STUBEOF'
#!/bin/bash
printf '01:00.0 VGA compatible controller: NVIDIA Corporation AD107M [GeForce RTX 4050 Max-Q / Mobile]\n'
case "${IGPU:-none}" in
  intel) printf '00:02.0 VGA compatible controller: Intel Corporation Raptor Lake-P [UHD Graphics]\n' ;;
  amd)   printf '05:00.0 VGA compatible controller: Advanced Micro Devices, Inc. [AMD/ATI] Rembrandt\n' ;;
esac
STUBEOF
cat >"$STUB/pacman" <<'STUBEOF'
#!/bin/bash
case "${1:-}" in
  -Si) exit 1 ;;
  -Qq) [[ $2 == nvidia-utils ]] && exit 0; exit 1 ;;
esac
printf 'pacman %s\n' "$*" >>"$CALL_LOG"
exit 0
STUBEOF
cat >"$STUB/pacman-conf" <<'STUBEOF'
#!/bin/bash
printf 'core\nextra\nmultilib\n'
STUBEOF
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
"$@"
STUBEOF
for t in mkinitcpio paru; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"$CALL_LOG"\nexit 0\n' "$t" >"$STUB/$t"
done
chmod +x "$STUB"/*

MODULES="$TMP/modules/$(uname -r)"; mkdir -p "$MODULES"; printf 'linux\n' >"$MODULES/pkgbase"

HOME_DIR="$TMP/home"
run_nvidia() {
  rm -rf "${TMP:?}/home"; mkdir -p "$HOME_DIR/.config/uwsm"
  : >"$LOG"
  HOME="$HOME_DIR" CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" IGPU="$1" \
    HYPRSIMPLE_MODULES_DIR="$TMP/modules" \
    bash -c '
      set -uo pipefail
      RED=""; GREEN=""; YELLOW=""; NC=""
      AUR_HELPER="paru"; DOTFILES_DIR="'"$REPO"'"; FAILED_PACKAGES=()
      source "'"$FUNCS"'"
      detect_and_install_nvidia
    ' >"$TMP/out" 2>&1
}
env_file() { cat "$HOME_DIR/.config/uwsm/env" 2>/dev/null; }

# --- a hybrid machine gets no global override -------------------------------

for igpu in intel amd; do
  run_nvidia "$igpu"
  check "with an $igpu iGPU, GLX is not forced to nvidia" \
    "$(env_file | grep -c '__GLX_VENDOR_LIBRARY_NAME')" "0"
  check "and VA-API is not either ($igpu)" \
    "$(env_file | grep -c 'LIBVA_DRIVER_NAME')" "0"
  check "and prime-run is named as the way to use the dGPU ($igpu)" \
    "$(grep -c 'prime-run' "$TMP/out")" "1"
done

# The driver still installs. Without this the fix could be a way to skip NVIDIA
# support altogether on every laptop.
run_nvidia intel
check "the driver is still installed on a hybrid machine" \
  "$(grep -c 'nvidia-open-dkms' "$LOG")" "1"
check "and the setup still reports completion" \
  "$(grep -c 'NVIDIA setup complete' "$TMP/out")" "1"

# --- an NVIDIA-only machine still gets it -----------------------------------

run_nvidia none
check "with no iGPU the GLX vendor is still exported" \
  "$(env_file | grep -c 'export __GLX_VENDOR_LIBRARY_NAME=nvidia')" "1"
check "and the backend with it" "$(env_file | grep -c 'NVD_BACKEND=direct')" "1"
check "and the initramfs is rebuilt" "$(grep -c '^mkinitcpio' "$LOG")" "1"

# --- the migration, for machines already carrying the block -----------------

mk_env() {
  rm -rf "${TMP:?}/mhome"; mkdir -p "$TMP/mhome/.config/uwsm"
  cat >"$TMP/mhome/.config/uwsm/env" <<'ENVEOF'
export XCURSOR_SIZE=24
export GDK_BACKEND="wayland,x11,*"

# NVIDIA (Turing+ with GSP firmware) - auto-detected by installer
export NVD_BACKEND=direct
export LIBVA_DRIVER_NAME=nvidia
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export XCURSOR_THEME=Bibata
ENVEOF
}
run_migration() {
  HOME="$TMP/mhome" IGPU="$1" PATH="$STUB:/usr/bin:/bin" \
    bash "$MIGRATION" >"$TMP/mout" 2>&1
}
menv() { cat "$TMP/mhome/.config/uwsm/env"; }

mk_env
check "the fixture starts with the block present" \
  "$(menv | grep -c '__GLX_VENDOR_LIBRARY_NAME')" "1"
run_migration intel
check "the migration removes the GLX override" \
  "$(menv | grep -c '__GLX_VENDOR_LIBRARY_NAME')" "0"
check "and the VA-API one" "$(menv | grep -c 'LIBVA_DRIVER_NAME')" "0"
check "and the backend" "$(menv | grep -c 'NVD_BACKEND')" "0"
check "and its comment line" "$(menv | grep -c 'auto-detected by installer')" "0"
check "and keeps everything else" \
  "$(menv | grep -c 'GDK_BACKEND\|XCURSOR_SIZE\|XCURSOR_THEME')" "3"
check "and leaves a backup" \
  "$([[ -f $TMP/mhome/.config/uwsm/env.bak ]] && echo yes || echo no)" "yes"

run_migration intel
check "re-running changes nothing more" \
  "$(menv | grep -c 'GDK_BACKEND\|XCURSOR_SIZE\|XCURSOR_THEME')" "3"

# An NVIDIA-only machine must keep the block.
mk_env
run_migration none
check "a machine with no iGPU keeps the block" \
  "$(menv | grep -c '__GLX_VENDOR_LIBRARY_NAME')" "1"
check "and says why" "$(grep -c 'no integrated GPU' "$TMP/mout")" "1"
check "and writes no backup, having changed nothing" \
  "$([[ -f $TMP/mhome/.config/uwsm/env.bak ]] && echo yes || echo no)" "no"

# A file that never had the block is untouched.
rm -rf "${TMP:?}/mhome"; mkdir -p "$TMP/mhome/.config/uwsm"
printf 'export GDK_BACKEND=wayland\n' >"$TMP/mhome/.config/uwsm/env"
run_migration intel
check "an env file without the block is left alone" \
  "$(menv)" "export GDK_BACKEND=wayland"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
