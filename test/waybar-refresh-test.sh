#!/bin/bash
# Checks the screen recording indicator and the waybar refresh command against
# fixtures. Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INDICATOR="$REPO/.local/bin/waybar-screenrecording.sh"
REFRESH="$REPO/.local/bin/hyprsimple-refresh-waybar.sh"
REFRESH_CONFIG="$REPO/.local/bin/hyprsimple-refresh-config.sh"
RESTART="$REPO/.local/bin/hyprsimple-restart-waybar.sh"
SCREEN_RECORD="$REPO/.local/bin/screen-record.sh"
SHIPPED_CONFIG="$REPO/test/fixtures/waybar/config.jsonc.shipped"
SHIPPED_STYLE="$REPO/test/fixtures/waybar/style.css.shipped"
MIGRATION="$REPO/migrations/1788087069.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# Every fixture home goes through this before a run touches it. An empty path
# would make later rm/cp calls operate against the real $HOME, which is the
# environment this suite runs in.
must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'fixture: refusing to use path [%s], expected a path under %s\n' "${1:-}" "$TMP" >&2
    exit 2
  fi
}

# Strip JSONC's // comments and trailing commas for parsing only. Never write
# the stripped form back anywhere.
strip_jsonc() {
  sed -E 's#//.*##' "$1" | perl -0pe 's/,(\s*[}\]])/$1/g'
}

# ---- the indicator, with a real wl-screenrec sentinel on PATH ------------
# This block needs a REAL pgrep so the indicator can find the sentinel. The
# stub PATH installed further down neutralises pgrep for every check after
# this one, so the indicator checks run first, against a PATH of their own.

REAL_PGREP="$(command -v pgrep)"
SENTINEL_BIN="$TMP/sentinel-bin"
mkdir -p "$SENTINEL_BIN"
# A copied binary named wl-screenrec, not a renamed argument or a shell
# function: pgrep -x matches on the process's comm name, which for a shell
# function or a relaunch under a different argv0 would not be "wl-screenrec".
cp "$(command -v sleep)" "$SENTINEL_BIN/wl-screenrec"
chmod +x "$SENTINEL_BIN/wl-screenrec"

"$SENTINEL_BIN/wl-screenrec" 300 &
sentinel_pid=$!
# Give the process a moment to be visible to pgrep before we query for it.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  "$REAL_PGREP" -x wl-screenrec >/dev/null && break
  sleep 0.1
done

indicator_running="$("$INDICATOR")"
kill "$sentinel_pid" 2>/dev/null
wait "$sentinel_pid" 2>/dev/null

running_text=$(printf '%s' "$indicator_running" | grep -o '"text": "[^"]*"' | cut -d'"' -f4)
running_class=$(printf '%s' "$indicator_running" | grep -o '"class": "[^"]*"' | cut -d'"' -f4)

check "the indicator's text is non-empty while wl-screenrec runs" \
  "$([[ -n $running_text ]] && echo nonempty || echo empty)" "nonempty"
check "the indicator reports the active class while wl-screenrec runs" \
  "$running_class" "active"

# Confirm nothing is left running before the stub-PATH checks begin.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  "$REAL_PGREP" -x wl-screenrec >/dev/null || break
  sleep 0.1
done

# ---- the indicator, with none running -------------------------------------
# No sentinel process exists on this PATH, real pgrep included, so this
# exercises the "nothing running" branch honestly rather than vacuously.

indicator_idle="$("$INDICATOR")"
idle_text=$(printf '%s' "$indicator_idle" | grep -o '"text": "[^"]*"' | cut -d'"' -f4)
idle_has_class=$(printf '%s' "$indicator_idle" | grep -q '"class"' && echo yes || echo no)

check "the indicator's text is empty with nothing running" "$idle_text" ""
check "the indicator carries no class with nothing running" "$idle_has_class" "no"

# ---- stub PATH for everything from here on --------------------------------
# From here on checks must NOT be able to touch the real session: the refresh
# script ends by calling hyprsimple-restart-waybar.sh, which calls pkill and
# uwsm. A stub pgrep that exits 1 by default also keeps that restart's own
# internals (should it ever grow a pgrep check) from seeing the real session.
STUB_BIN="$TMP/stub-bin"
mkdir -p "$STUB_BIN"
for stub in pgrep pkill uwsm; do
  printf '#!/bin/sh\nexit 1\n' >"$STUB_BIN/$stub"
  chmod +x "$STUB_BIN/$stub"
done
export PATH="$STUB_BIN:$PATH"

# ---- restart-waybar.sh: --if-running only restarts a running waybar -------
# An exit status alone can't tell a skipped launch from a completed one,
# since both are 0, so a uwsm stub that writes a marker file is used instead,
# and the marker's presence or absence is what gets asserted.

ifrun_marker="$TMP/ifrun-launched"
ifrun_bin="$TMP/ifrun-bin"
mkdir -p "$ifrun_bin"
printf '#!/bin/sh\ntouch "%s"\n' "$ifrun_marker" >"$ifrun_bin/uwsm"
chmod +x "$ifrun_bin/uwsm"

# not running: the shared stub pgrep (installed above, exits 1) is still
# first on this PATH.
rm -f "$ifrun_marker"
PATH="$ifrun_bin:$PATH" bash "$RESTART" --if-running >/dev/null 2>&1
marker_seen=no
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f $ifrun_marker ]] && { marker_seen=yes; break; }
  sleep 0.1
done
check "--if-running launches nothing when waybar is not running" "$marker_seen" "no"

# running: a second, separate stub dir gives pgrep exit 0, prepended only for
# this call so the shared stub is left untouched.
running_pgrep_bin="$TMP/running-pgrep-bin"
mkdir -p "$running_pgrep_bin"
printf '#!/bin/sh\nexit 0\n' >"$running_pgrep_bin/pgrep"
chmod +x "$running_pgrep_bin/pgrep"

rm -f "$ifrun_marker"
saved_path="$PATH"
PATH="$running_pgrep_bin:$ifrun_bin:$PATH" bash "$RESTART" --if-running >/dev/null 2>&1
marker_seen=no
for _ in 1 2 3 4 5 6 7 8 9 10; do
  [[ -f $ifrun_marker ]] && { marker_seen=yes; break; }
  sleep 0.1
done
PATH="$saved_path"
check "--if-running launches waybar when it is already running" "$marker_seen" "yes"

# ---- the shipped config.jsonc fixture -------------------------------------

stripped="$TMP/shipped-stripped.json"
strip_jsonc "$SHIPPED_CONFIG" >"$stripped"

if jq -e . "$stripped" >/dev/null 2>&1; then
  pass "the shipped config.jsonc parses as JSON once comments and trailing commas are stripped"
else
  fail "the shipped config.jsonc parses as JSON once comments and trailing commas are stripped"
fi

check "custom/screenrecording carries signal 8" \
  "$(jq -r '."custom/screenrecording".signal // empty' "$stripped")" "8"

check "custom/screenrecording carries no interval key" \
  "$(jq -e '."custom/screenrecording" | has("interval")' "$stripped")" "false"

check "modules-right lists custom/screenrecording" \
  "$(jq -e '."modules-right" | index("custom/screenrecording") != null' "$stripped")" "true"

check "custom/screenrecording's on-click names screen-record.sh" \
  "$(jq -r '."custom/screenrecording"."on-click"' "$stripped" | grep -c 'screen-record\.sh')" "1"

# ---- consolidating restarts did not scatter the relaunch or drop the signal

hits=$(grep -rlE 'uwsm app -- waybar|nohup waybar' "$REPO/.local/bin" "$REPO/install.sh" 2>/dev/null | grep -v 'hyprsimple-restart-waybar\.sh$' | wc -l)
check "no file besides hyprsimple-restart-waybar.sh relaunches waybar directly" "$hits" "0"

if grep -q 'RTMIN+8' "$SCREEN_RECORD"; then
  pass "screen-record.sh still signals waybar with RTMIN+8"
else
  fail "screen-record.sh still signals waybar with RTMIN+8"
fi

# ---- refresh: a non-default position survives the refresh -----------------

fixture_home="$TMP/home-refresh"
must_be_fixture "$fixture_home"
mkdir -p "$fixture_home/.local/bin" "$fixture_home/.config/waybar"
cp "$REFRESH_CONFIG" "$fixture_home/.local/bin/hyprsimple-refresh-config.sh"
cp "$RESTART" "$fixture_home/.local/bin/hyprsimple-restart-waybar.sh"
chmod +x "$fixture_home/.local/bin/"*.sh

install_root="$TMP/install-refresh"
must_be_fixture "$install_root"
mkdir -p "$install_root/.config/waybar"
cp "$SHIPPED_CONFIG" "$install_root/.config/waybar/config.jsonc"
: >"$install_root/.config/waybar/style.css"

sed 's/"position": "top"/"position": "bottom"/' "$SHIPPED_CONFIG" \
  >"$fixture_home/.config/waybar/config.jsonc"
: >"$fixture_home/.config/waybar/style.css"

HOME="$fixture_home" HYPRSIMPLE_PATH="$install_root" bash "$REFRESH" >"$TMP/refresh_out" 2>&1
refresh_status=$?

check "the refresh command exits 0" "$refresh_status" "0"

check "the non-default position survives the refresh" \
  "$(grep -oE '"position": "[a-z]+"' "$fixture_home/.config/waybar/config.jsonc")" \
  '"position": "bottom"'

# ---- the migration: pristine, edited and idempotent installs -------------

migrate_install_root="$TMP/install-migrate"
must_be_fixture "$migrate_install_root"
mkdir -p "$migrate_install_root/.config/waybar"
cp "$SHIPPED_CONFIG" "$migrate_install_root/.config/waybar/config.jsonc"
cp "$SHIPPED_STYLE" "$migrate_install_root/.config/waybar/style.css"

# an old-but-pristine install: config.jsonc predates the indicator (derived
# here from the shipped fixture, not from git history) but was never hand
# edited, so its checksum is one of CONFIG_SUMS's entries and the migration's
# match-and-copy branch is the one that must bring it up to date.
old_pristine_home="$TMP/home-migrate-old-pristine"
must_be_fixture "$old_pristine_home"
mkdir -p "$old_pristine_home/.local/bin" "$old_pristine_home/.config/waybar"
cp "$RESTART" "$old_pristine_home/.local/bin/hyprsimple-restart-waybar.sh"
chmod +x "$old_pristine_home/.local/bin/"*.sh
sed -e 's/"battery", "custom\/screenrecording", "clock"/"battery", "clock"/' \
    -e '/^    "custom\/screenrecording": {$/,/^    },$/d' \
    "$SHIPPED_CONFIG" >"$old_pristine_home/.config/waybar/config.jsonc"
cp "$SHIPPED_STYLE" "$old_pristine_home/.config/waybar/style.css"

old_sum=$(md5sum "$old_pristine_home/.config/waybar/config.jsonc" | cut -d' ' -f1)
config_sums_block_check=$(sed -n '/^CONFIG_SUMS=(/,/^)/p' "$MIGRATION")
check "the reconstructed old config.jsonc's checksum is one CONFIG_SUMS lists" \
  "$(grep -c "$old_sum" <<<"$config_sums_block_check")" "1"

HOME="$old_pristine_home" HYPRSIMPLE_PATH="$migrate_install_root" bash "$MIGRATION" \
  >"$TMP/migrate_old_pristine_out" 2>&1

check "an old pristine config.jsonc is replaced by the install's version after the migration" \
  "$(cmp -s "$old_pristine_home/.config/waybar/config.jsonc" "$migrate_install_root/.config/waybar/config.jsonc" && echo same || echo different)" \
  "same"

# a pristine install: the user's files already match what ships
pristine_home="$TMP/home-migrate-pristine"
must_be_fixture "$pristine_home"
mkdir -p "$pristine_home/.local/bin" "$pristine_home/.config/waybar"
cp "$RESTART" "$pristine_home/.local/bin/hyprsimple-restart-waybar.sh"
chmod +x "$pristine_home/.local/bin/"*.sh
cp "$SHIPPED_CONFIG" "$pristine_home/.config/waybar/config.jsonc"
cp "$SHIPPED_STYLE" "$pristine_home/.config/waybar/style.css"

HOME="$pristine_home" HYPRSIMPLE_PATH="$migrate_install_root" bash "$MIGRATION" \
  >"$TMP/migrate_pristine_out" 2>&1

check "a config.jsonc identical to the shipped fixture matches the install's version after the migration" \
  "$(cmp -s "$pristine_home/.config/waybar/config.jsonc" "$migrate_install_root/.config/waybar/config.jsonc" && echo same || echo different)" \
  "same"

# an edited install: config.jsonc carries a line hyprsimple never shipped
edited_home="$TMP/home-migrate-edited"
must_be_fixture "$edited_home"
mkdir -p "$edited_home/.local/bin" "$edited_home/.config/waybar"
cp "$RESTART" "$edited_home/.local/bin/hyprsimple-restart-waybar.sh"
chmod +x "$edited_home/.local/bin/"*.sh
{ cat "$SHIPPED_CONFIG"; echo "// a user's own comment"; } >"$edited_home/.config/waybar/config.jsonc"
cp "$SHIPPED_STYLE" "$edited_home/.config/waybar/style.css"

edited_before=$(md5sum "$edited_home/.config/waybar/config.jsonc" | cut -d' ' -f1)
HOME="$edited_home" HYPRSIMPLE_PATH="$migrate_install_root" bash "$MIGRATION" \
  >"$TMP/migrate_edited_out" 2>&1
edited_after=$(md5sum "$edited_home/.config/waybar/config.jsonc" | cut -d' ' -f1)

check "a config.jsonc with an added line is byte-unchanged by the migration" "$edited_after" "$edited_before"

check "the migration points an edited install at hyprsimple-refresh-waybar.sh" \
  "$(grep -c 'hyprsimple-refresh-waybar\.sh' "$TMP/migrate_edited_out")" "1"

# the migration must end by restarting waybar so config changes take effect
restart_home="$TMP/home-migrate-restart-check"
must_be_fixture "$restart_home"
mkdir -p "$restart_home/.local/bin" "$restart_home/.config/waybar"
restart_marker="$TMP/restart-called"
rm -f "$restart_marker"
printf '#!/bin/sh\ntouch "%s"\n' "$restart_marker" >"$restart_home/.local/bin/hyprsimple-restart-waybar.sh"
chmod +x "$restart_home/.local/bin/hyprsimple-restart-waybar.sh"
cp "$SHIPPED_CONFIG" "$restart_home/.config/waybar/config.jsonc"
cp "$SHIPPED_STYLE" "$restart_home/.config/waybar/style.css"

HOME="$restart_home" HYPRSIMPLE_PATH="$migrate_install_root" bash "$MIGRATION" >/dev/null 2>&1

check "the migration restarts waybar so config changes take effect" \
  "$([[ -f $restart_marker ]] && echo called || echo not-called)" "called"

# a second run of the migration against an already-migrated home changes nothing
idem_before=$(find "$pristine_home" -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
HOME="$pristine_home" HYPRSIMPLE_PATH="$migrate_install_root" bash "$MIGRATION" >/dev/null 2>&1
idem_after=$(find "$pristine_home" -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)

check "a second migration run changes no file in the fixture home" "$idem_after" "$idem_before"

# each vendored fixture's checksum must be listed in the migration's matching
# array, so a fixture that drifts out of step with the migration reports itself
config_shipped_sum=$(md5sum "$SHIPPED_CONFIG" | cut -d' ' -f1)
style_shipped_sum=$(md5sum "$SHIPPED_STYLE" | cut -d' ' -f1)
config_sums_block=$(sed -n '/^CONFIG_SUMS=(/,/^)/p' "$MIGRATION")
style_sums_block=$(sed -n '/^STYLE_SUMS=(/,/^)/p' "$MIGRATION")

check "the shipped config.jsonc fixture's checksum is listed in the migration's CONFIG_SUMS" \
  "$(grep -c "$config_shipped_sum" <<<"$config_sums_block")" "1"

check "the shipped style.css fixture's checksum is listed in the migration's STYLE_SUMS" \
  "$(grep -c "$style_shipped_sum" <<<"$style_sums_block")" "1"


# ---- screen-record.sh stop mode -----------------------------------------
# The indicator's on-click passes `stop`. Without that branch a click while
# nothing is recording falls through to the region branch and runs slurp, so
# the check that matters is that slurp is never reached.

# screen-record.sh exits early when its output directory is missing, and the
# default is $HOME/Videos, which a CI runner does not have. Point it at the
# fixture so these checks measure the stop branch rather than that guard.
stop_bin="$TMP/stop-bin"
stop_out="$TMP/stop-videos"
mkdir -p "$stop_bin" "$stop_out"
for stub in slurp dunstify pkill wl-screenrec wf-recorder; do
  printf '#!/bin/sh\necho "%s" >>"%s/calls"\nexit 0\n' "$stub" "$stop_bin" >"$stop_bin/$stub"
  chmod +x "$stop_bin/$stub"
done

printf '#!/bin/sh\nexit 1\n' >"$stop_bin/pgrep"
chmod +x "$stop_bin/pgrep"
: >"$stop_bin/calls"
PATH="$stop_bin:$PATH" XDG_VIDEOS_DIR="$stop_out" bash "$REPO/.local/bin/screen-record.sh" stop >/dev/null 2>&1
check "screen-record.sh stop runs nothing when idle" \
  "$(wc -l <"$stop_bin/calls")" "0"

printf '#!/bin/sh\nexit 0\n' >"$stop_bin/pgrep"
chmod +x "$stop_bin/pgrep"
: >"$stop_bin/calls"
PATH="$stop_bin:$PATH" XDG_VIDEOS_DIR="$stop_out" bash "$REPO/.local/bin/screen-record.sh" stop >/dev/null 2>&1
if grep -q '^pkill$' "$stop_bin/calls" && ! grep -q '^slurp$' "$stop_bin/calls"; then
  pass "screen-record.sh stop stops a running recording without a selector"
else
  fail "screen-record.sh stop stops a running recording without a selector"
fi

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
