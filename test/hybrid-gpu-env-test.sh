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
# set_env_block is extracted too. detect_and_install_nvidia calls it now
# instead of `cat >>`, and a function that is not extracted is simply absent
# here: the block is never written and every check about the env file fails for
# a reason that has nothing to do with what it is testing.
sed -n '/^set_env_block() {/,/^}/p' "$REPO/install.sh" >>"$FUNCS"
sed -n '/^install_packages() {/,/^}/p' "$REPO/install.sh" >>"$FUNCS"
for marker in 'detect_and_install_nvidia() {' 'set_env_block() {' 'other_gpu' '__GLX_VENDOR_LIBRARY_NAME' \
  'supergfxctl' 'NVIDIA setup complete (arch: $GPU_ARCH)'; do
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
  -Qq)
    [[ $2 == nvidia-utils ]] && exit 0
    # Whether the AUR build landed is the test's to say, the way INSTALLED is
    # in nvidia-install-test.sh. Asked of this stub and never of PATH, because
    # a machine that has the real supergfxctl would otherwise answer for it.
    [[ $2 == supergfxctl && ${GFX_INSTALLED:-yes} == yes ]] && exit 0
    exit 1 ;;
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
# systemctl is stubbed for the same reason pacman is. The sudo stub runs what
# follows it, so without this `sudo systemctl enable --now supergfxd` would
# reach the real one.
for t in mkinitcpio paru systemctl; do
  printf '#!/bin/bash\nprintf "%s %%s\\n" "$*" >>"$CALL_LOG"\nexit 0\n' "$t" >"$STUB/$t"
done
chmod +x "$STUB"/*

MODULES="$TMP/modules/$(uname -r)"; mkdir -p "$MODULES"; printf 'linux\n' >"$MODULES/pkgbase"

HOME_DIR="$TMP/home"
# Where install.sh is told to put supergfxd's config. Set on every run, so no
# scenario here can write to /etc.
GFX_CONF="$TMP/etc/supergfxd.conf"
mkdir -p "$TMP/etc"
run_nvidia() {
  rm -rf "${TMP:?}/home"; mkdir -p "$HOME_DIR/.config/uwsm"
  : >"$LOG"
  HOME="$HOME_DIR" CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" IGPU="$1" \
    GFX_INSTALLED="${2:-yes}" HYPRSIMPLE_SUPERGFXD_CONF="$GFX_CONF" \
    HYPRSIMPLE_MODULES_DIR="$TMP/modules" \
    bash -c '
      set -uo pipefail
      RED=""; GREEN=""; YELLOW=""; NC=""
      AUR_HELPER="paru"; AUR_CONFIRM=(); DOTFILES_DIR="'"$REPO"'"; FAILED_PACKAGES=()
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

# --- a hybrid machine gets supergfxctl, and the means to switch --------------
#
# Nothing in hyprsimple could turn the discrete card off, or back on. A laptop
# was found in supergfxd's Vfio mode with its card unusable, put there by hand
# with a switcher hyprsimple knew nothing about. The installer now sets that
# switcher up on the one kind of machine that needs it.

rm -f "$GFX_CONF"
run_nvidia intel
check "on a hybrid machine the AUR helper is asked for supergfxctl" \
  "$(grep -c '^paru .*supergfxctl' "$LOG")" "1"
check "and supergfxd's config is written" \
  "$([[ -f $GFX_CONF ]] && echo yes || echo no)" "yes"
check "in Hybrid mode, which is what the machine already is" \
  "$(grep -c '"mode": "Hybrid"' "$GFX_CONF" 2>/dev/null)" "1"
check "and the service is enabled and started" \
  "$(grep -c '^systemctl enable --now supergfxd' "$LOG")" "1"
check "and the toggle is named" \
  "$(grep -c 'toggle-hybrid-gpu.sh' "$TMP/out")" "1"

# A re-run must not undo a choice. install.sh is meant to be run again, and a
# machine its owner switched to Integrated has to stay there.
printf '{\n  "mode": "Integrated"\n}\n' >"$GFX_CONF"
before="$(cat "$GFX_CONF")"
run_nvidia intel
check "an existing config is left exactly as it was" "$(cat "$GFX_CONF")" "$before"
check "and the service is still enabled" \
  "$(grep -c '^systemctl enable --now supergfxd' "$LOG")" "1"

# The AUR build is a Rust compile and can fail. That must cost the machine GPU
# switching and nothing else.
rm -f "$GFX_CONF"
run_nvidia intel no
check "a build that did not land leaves the function returning 0" "$?" "0"
check "and writes no config" "$([[ -e $GFX_CONF ]] && echo yes || echo no)" "no"
check "and starts no service" "$(grep -c '^systemctl' "$LOG")" "0"
check "and says the switch is unavailable" \
  "$(grep -c 'supergfxctl did not install' "$TMP/out")" "1"
check "and the setup still reports completion" \
  "$(grep -c 'NVIDIA setup complete' "$TMP/out")" "1"

# A machine whose only card is NVIDIA has nothing to switch between.
rm -f "$GFX_CONF"
run_nvidia none
check "an NVIDIA-only machine is not given supergfxctl" \
  "$(grep -c 'supergfxctl' "$LOG")" "0"
check "and gets no config" "$([[ -e $GFX_CONF ]] && echo yes || echo no)" "no"
check "and no service call" "$(grep -c '^systemctl' "$LOG")" "0"

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
