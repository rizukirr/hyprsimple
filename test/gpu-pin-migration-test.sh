#!/bin/bash
# install.sh pinned Hyprland to one GPU: a udev rule naming it under /dev/dri
# and an AQ_DRM_DEVICES export in ~/.config/uwsm/env-hyprland. A monitor on a
# port wired to the other card then had nothing to drive it. The pin is gone
# from the installer, and this migration takes it off machines already
# installed.
#
# Nothing here runs an installer or touches /etc. The migration runs against
# throwaway homes and a throwaway rules directory, with sudo and udevadm
# stubbed and every call logged.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1790792769.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

if [[ -f $MIGRATION ]]; then
  pass "the migration exists"
else
  fail "the migration is missing at $MIGRATION, so nothing below is testing it"
fi

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"
# sudo runs what follows it, so rm reaches the throwaway directory and udevadm
# reaches its stub. Both calls are logged, so a run that should make none can
# be checked.
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALL_LOG"
"$@"
STUBEOF
printf '#!/bin/bash\nprintf "udevadm %%s\\n" "$*" >>"$CALL_LOG"\nexit 0\n' >"$STUB/udevadm"
chmod +x "$STUB"/*

HOME_DIR="$TMP/home"
ENV_FILE="$HOME_DIR/.config/uwsm/env-hyprland"
RULES="$TMP/rules"
run_migration() {
  : >"$LOG"
  HOME="$HOME_DIR" CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" \
    HYPRSIMPLE_UDEV_RULE_DIRS="$TMP/sys-rules $RULES" \
    bash "$MIGRATION" >"$TMP/out" 2>&1
}
fresh() { rm -rf "$HOME_DIR" "$RULES"; mkdir -p "$HOME_DIR/.config/uwsm" "$RULES"; }
envf() { cat "$ENV_FILE" 2>/dev/null; }

# --- the marked block set_env_block writes ----------------------------------

fresh
cat >"$ENV_FILE" <<'ENVEOF'
export HYPRLAND_TRACE=1

# >>> hyprsimple gpu >>>
# Primary GPU: Intel (priority: Intel > AMD > NVIDIA)
export AQ_DRM_DEVICES="/dev/dri/intel-gpu"
# <<< hyprsimple gpu <<<
ENVEOF
original="$(envf)"
run_migration
check "the migration exits 0" "$?" "0"
check "the marked block is gone" \
  "$(envf | grep -c 'AQ_DRM_DEVICES\|hyprsimple gpu\|Primary GPU')" "0"
check "and the other export stays" "$(envf | grep -c '^export HYPRLAND_TRACE=1$')" "1"
check "and the backup holds the original" "$(cat "$ENV_FILE.bak")" "$original"
check "and the output says where the backup is" \
  "$(grep -c 'env-hyprland.bak' "$TMP/out")" "1"

# A second run has nothing left to remove, and must not overwrite the backup
# with a file that no longer holds the original.
after_first="$(envf)"
run_migration
check "a second run leaves the file as it was" "$(envf)" "$after_first"
check "and the backup as it was" "$(cat "$ENV_FILE.bak")" "$original"

# --- the unmarked form from before the markers existed ----------------------

fresh
printf '# Primary GPU: AMD (priority: Intel > AMD > NVIDIA)\nexport AQ_DRM_DEVICES="/dev/dri/amd-gpu"\nexport GDK_SCALE=2\n' >"$ENV_FILE"
run_migration
check "the unmarked comment and export go" \
  "$(envf | grep -c 'AQ_DRM_DEVICES\|Primary GPU')" "0"
check "and the rest stays" "$(envf)" "export GDK_SCALE=2"

# --- a file without the block ------------------------------------------------

fresh
printf 'export GDK_SCALE=2\n' >"$ENV_FILE"
run_migration
check "a file without the block is left alone" "$(envf)" "export GDK_SCALE=2"
check "and gets no backup" "$([[ -e $ENV_FILE.bak ]] && echo yes || echo no)" "no"

# --- no file at all ----------------------------------------------------------

fresh
rm -f "$ENV_FILE"
run_migration
check "with no env-hyprland the migration still exits 0" "$?" "0"
check "and creates none" "$([[ -e $ENV_FILE ]] && echo yes || echo no)" "no"

# --- the udev rule -----------------------------------------------------------

for vendor in intel amd nvidia; do
  fresh
  printf 'KERNEL=="card[0-9]*", SYMLINK+="dri/%s-gpu"\n' "$vendor" >"$RULES/99-$vendor-gpu.rules"
  run_migration
  check "the $vendor rule is removed" \
    "$([[ -e $RULES/99-$vendor-gpu.rules ]] && echo yes || echo no)" "no"
  check "and udev is reloaded ($vendor)" \
    "$(grep -c '^udevadm control --reload' "$LOG")" "1"
done

# A rule that is not hyprsimple's is not touched, and with nothing to remove
# nothing runs under sudo.
fresh
printf 'KERNEL=="card0", SYMLINK+="dri/mine"\n' >"$RULES/99-mine.rules"
run_migration
check "someone else's rule stays" \
  "$([[ -e $RULES/99-mine.rules ]] && echo yes || echo no)" "yes"
check "and nothing runs under sudo without a rule to remove" \
  "$(grep -c '^sudo' "$LOG")" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
