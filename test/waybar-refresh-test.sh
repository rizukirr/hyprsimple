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

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
