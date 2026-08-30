#!/bin/bash
# Checks the hyprlock/hypridle/xdph split and its migration against fixtures.
# Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATION="$REPO/migrations/1788076006.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The migration ends by nothing that touches a daemon directly, but model the
# stub block on dunst-split-test.sh anyway: pgrep, pkill and uwsm do not
# consult HOME, and a future edit to this migration may grow a restart call.
STUB_BIN="$TMP/stub-bin"
mkdir -p "$STUB_BIN"
for stub in pgrep pkill uwsm; do
  printf '#!/bin/sh\nexit 1\n' >"$STUB_BIN/$stub"
  chmod +x "$STUB_BIN/$stub"
done
export PATH="$STUB_BIN:$PATH"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# Every fixture home goes through this before a migration run touches it. An
# empty path would make later rm/cp calls operate against the real $HOME,
# which is the environment this suite runs in.
must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'fixture: refusing to use path [%s], expected a path under %s\n' "${1:-}" "$TMP" >&2
    exit 2
  fi
}

# The three files as they stood at the commit before this branch, vendored
# under test/fixtures/hypr so the suite never reads git history.
PRESPLIT_HYPRIDLE="$REPO/test/fixtures/hypr/hypridle.presplit.conf"
PRESPLIT_HYPRLOCK="$REPO/test/fixtures/hypr/hyprlock.presplit.conf"
PRESPLIT_XDPH="$REPO/test/fixtures/hypr/xdph.presplit.conf"

# ---- vendored fixtures match the checksums the migration recognises -----

for pair in "hypridle.conf:hypridle" "xdph.conf:xdph" "hyprlock.conf:hyprlock"; do
  name=${pair%%:*}
  stem=${pair##*:}
  sum=$(md5sum "$REPO/test/fixtures/hypr/$stem.presplit.conf" | cut -d' ' -f1)
  if grep -q "$name:$sum" "$MIGRATION"; then
    pass "the vendored $name fixture matches the checksum the migration recognises"
  else
    fail "the vendored $name fixture matches the checksum the migration recognises"
  fi
done

# ---- the hypridle fragments concatenate back to the pre-split file ------

concat="$TMP/concat-hypridle.conf"
cat "$REPO/default/hypr/hypridle/10-general.conf" \
  "$REPO/default/hypr/hypridle/20-brightness.conf" \
  "$REPO/default/hypr/hypridle/30-lock.conf" \
  "$REPO/default/hypr/hypridle/40-dpms.conf" \
  "$REPO/default/hypr/hypridle/50-suspend.conf" \
  >"$concat"

if cmp -s "$concat" "$PRESPLIT_HYPRIDLE"; then
  pass "the hypridle fragments concatenate to the pre-split hypridle.conf"
else
  fail "the hypridle fragments concatenate to the pre-split hypridle.conf"
fi

# ---- hyprlock.conf and xdph.conf are unchanged by the split --------------

if cmp -s "$REPO/default/hypr/hyprlock.conf" "$PRESPLIT_HYPRLOCK"; then
  pass "default/hypr/hyprlock.conf is byte-identical to the pre-split version"
else
  fail "default/hypr/hyprlock.conf is byte-identical to the pre-split version"
fi

if cmp -s "$REPO/default/hypr/xdph.conf" "$PRESPLIT_XDPH"; then
  pass "default/hypr/xdph.conf is byte-identical to the pre-split version"
else
  fail "default/hypr/xdph.conf is byte-identical to the pre-split version"
fi

# ---- declining 30-lock.conf removes exactly its own lock listener --------
# general{}'s before_sleep_cmd also calls loginctl lock-session, so the count
# after dropping 30-lock.conf should be 1, not 0.

nolock="$TMP/concat-nolock.conf"
cat "$REPO/default/hypr/hypridle/10-general.conf" \
  "$REPO/default/hypr/hypridle/20-brightness.conf" \
  "$REPO/default/hypr/hypridle/40-dpms.conf" \
  "$REPO/default/hypr/hypridle/50-suspend.conf" \
  >"$nolock"

check "declining 30-lock.conf leaves exactly the general{} lock-session" \
  "$(grep -c 'loginctl lock-session' "$nolock")" "1"

# ---- migration: an unedited install is converted, symlink resolves ------

inst="$REPO"
unedited_home="$TMP/home-unedited"
must_be_fixture "$unedited_home"
mkdir -p "$unedited_home/.config/hypr"
cp "$PRESPLIT_HYPRIDLE" "$unedited_home/.config/hypr/hypridle.conf"
cp "$PRESPLIT_HYPRLOCK" "$unedited_home/.config/hypr/hyprlock.conf"
cp "$PRESPLIT_XDPH" "$unedited_home/.config/hypr/xdph.conf"

HOME="$unedited_home" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >"$TMP/mig_out" 2>&1
check "migration exits 0 for an unedited install" "$?" "0"

readlink -e "$unedited_home/.config/hypr/hyprsimple" >"$TMP/link_target"
check "readlink -e on .config/hypr/hyprsimple exits 0" "$?" "0"
check ".config/hypr/hyprsimple names the install fixture's default/hypr" \
  "$(cat "$TMP/link_target")" "$inst/default/hypr"

check "a hypridle.conf matching the shipped checksum is replaced" \
  "$(cmp -s "$unedited_home/.config/hypr/hypridle.conf" "$inst/.config/hypr/hypridle.conf" && echo same || echo diff)" "same"

check "no .pre-split file exists for the unedited hypridle.conf" \
  "$(find "$unedited_home/.config/hypr" -maxdepth 1 -name 'hypridle.conf.pre-split.*' | wc -l)" "0"

# ---- migration: an edited hyprlock.conf is preserved at .pre-split -------

edited_home="$TMP/home-edited"
must_be_fixture "$edited_home"
mkdir -p "$edited_home/.config/hypr"
cp "$PRESPLIT_HYPRIDLE" "$edited_home/.config/hypr/hypridle.conf"
sed 's/general {/general { # customized/' "$PRESPLIT_HYPRLOCK" >"$edited_home/.config/hypr/hyprlock.conf"
cp "$PRESPLIT_XDPH" "$edited_home/.config/hypr/xdph.conf"
cp "$edited_home/.config/hypr/hyprlock.conf" "$TMP/edited_hyprlock_original"

HOME="$edited_home" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
check "migration exits 0 for an edited hyprlock.conf" "$?" "0"

kept="$(find "$edited_home/.config/hypr" -maxdepth 1 -name 'hyprlock.conf.pre-split.*')"
if [[ -n $kept ]] && cmp -s "$kept" "$TMP/edited_hyprlock_original"; then
  pass "the edited hyprlock.conf is preserved byte-identical at .pre-split"
else
  fail "the edited hyprlock.conf is preserved byte-identical at .pre-split"
fi

if grep -q "^# Your previous hyprlock.conf is saved at $kept\$" "$edited_home/.config/hypr/hyprlock.conf"; then
  pass "the installed hyprlock.conf names its .pre-split path"
else
  fail "the installed hyprlock.conf names its .pre-split path"
fi

# ---- a second run changes nothing and writes no second .pre-split -------

snap=$(find "$edited_home" -type f -exec md5sum {} + | sort)
HOME="$edited_home" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
check "a second run is idempotent" "$(find "$edited_home" -type f -exec md5sum {} + | sort)" "$snap"

check "a second run writes no second .pre-split for hyprlock.conf" \
  "$(find "$edited_home/.config/hypr" -maxdepth 1 -name 'hyprlock.conf.pre-split.*' | wc -l)" "1"

# ---- migration: a strict-subset hyprlock.conf prints no empty header ----
# This is the maintainer's real case: their hyprlock.conf is missing settings
# the default carries, so diff produces no "> " lines and, unpatched, the
# invitation to uncomment lines that are not there stands alone.

subset_home="$TMP/home-subset"
must_be_fixture "$subset_home"
mkdir -p "$subset_home/.config/hypr"
sed '4d' "$REPO/default/hypr/hyprlock.conf" >"$subset_home/.config/hypr/hyprlock.conf"

HOME="$subset_home" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
subset_result="$subset_home/.config/hypr/hyprlock.conf"
subset_has_saved=$(grep -q '^# Your previous hyprlock.conf is saved at ' "$subset_result" && echo yes || echo no)
subset_has_header=$(grep -q 'Uncomment any you want to keep' "$subset_result" && echo yes || echo no)

check "a strict-subset hyprlock.conf gets the saved-at line but no empty uncomment header" \
  "$subset_has_saved:$subset_has_header" "yes:no"

# ---- migration: a hyprlock.conf with an extra line gets the full header -
# The counterpart to the subset check above: with an actual difference to
# report, both lines must appear, and the extra line among the comments.

extra_home="$TMP/home-extra"
must_be_fixture "$extra_home"
mkdir -p "$extra_home/.config/hypr"
EXTRA_LINE="# a line the shipped default does not contain"
cp "$REPO/default/hypr/hyprlock.conf" "$extra_home/.config/hypr/hyprlock.conf"
echo "$EXTRA_LINE" >>"$extra_home/.config/hypr/hyprlock.conf"

HOME="$extra_home" HYPRSIMPLE_PATH="$inst" bash "$MIGRATION" >/dev/null 2>&1
extra_result="$extra_home/.config/hypr/hyprlock.conf"
extra_has_saved=$(grep -q '^# Your previous hyprlock.conf is saved at ' "$extra_result" && echo yes || echo no)
extra_has_header=$(grep -q 'Uncomment any you want to keep' "$extra_result" && echo yes || echo no)
extra_has_line=$(grep -qF "#     $EXTRA_LINE" "$extra_result" && echo yes || echo no)

check "a hyprlock.conf with an extra line gets both header lines and the extra line as a comment" \
  "$extra_has_saved:$extra_has_header:$extra_has_line" "yes:yes:yes"

# ---- $DEFAULTS that does not resolve to real defaults: exits non-zero,
# nothing changes. $DEFAULTS itself is present (an install always ships
# default/hypr) but empty, the shape a broken or partial install takes; the
# guard that fires is the one after the symlink is created, not the leading
# "nothing to do" early exit, which is itself a silent, deliberate exit 0 for
# hosts with no hypr config at all and is not what this check is after.

nodef_inst="$TMP/install-nodefaults"
mkdir -p "$nodef_inst/default/hypr" "$nodef_inst/.config/hypr"
cp "$REPO/.config/hypr/hypridle.conf" "$nodef_inst/.config/hypr/hypridle.conf"
cp "$REPO/.config/hypr/hyprlock.conf" "$nodef_inst/.config/hypr/hyprlock.conf"
cp "$REPO/.config/hypr/xdph.conf" "$nodef_inst/.config/hypr/xdph.conf"
# $nodef_inst/default/hypr deliberately stays empty: no hypridle/10-general.conf.

nodef_home="$TMP/home-nodefaults"
must_be_fixture "$nodef_home"
mkdir -p "$nodef_home/.config/hypr"
cp "$PRESPLIT_HYPRIDLE" "$nodef_home/.config/hypr/hypridle.conf"
cp "$PRESPLIT_HYPRLOCK" "$nodef_home/.config/hypr/hyprlock.conf"
cp "$PRESPLIT_XDPH" "$nodef_home/.config/hypr/xdph.conf"
nodef_snap=$(find "$nodef_home" -type f -exec md5sum {} + | sort)

HOME="$nodef_home" HYPRSIMPLE_PATH="$nodef_inst" bash "$MIGRATION" >/dev/null 2>&1
status=$?
if ((status != 0)); then
  pass "with \$DEFAULTS not resolving, the migration exits non-zero"
else
  fail "with \$DEFAULTS not resolving, the migration exits non-zero"
fi

check "with \$DEFAULTS not resolving, no user file differs from before the run" \
  "$(find "$nodef_home" -type f -exec md5sum {} + | sort)" "$nodef_snap"

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
