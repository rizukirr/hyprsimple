#!/bin/bash
# The shipped hyprsunset.conf was TOML, and hyprsunset does not read TOML.
#
#   [[profile]]
#   name = "day"
#   start_time = 07:00
#   identity = true
#
# hyprsunset reads hyprlang, the same syntax as the rest of hypr's configs.
# Measured with hyprsunset v0.4.0 against the shipped file:
#
#   Config error in file .../hyprsunset.conf at line 7: Invalid config line
#   Loaded 0 profiles
#   Setting the temperature to 6000K (default)
#
# So the file's own invitation, "Uncomment and adjust to enable automatic
# nightlight", could not be acted on: no profile in it was ever read.
#
# And nothing started hyprsunset anyway. It appeared in autostart zero times,
# so the daemon only ever ran if SUPER+N was pressed, and only for that session.
#
# hyprsunset is a real dependency and is installed, so where it is present this
# suite hands it each config and reads its verdict rather than judging the
# syntax itself. Where it is absent, the checks that do not need it still run.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$REPO/.config/hypr/hyprsunset.conf"
MIGRATION="$REPO/migrations/1788644900.sh"
OLD_TOML="$REPO/test/fixtures/hypr/hyprsunset.conf.toml"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the syntax, without needing hyprsunset ---------------------------------

check "the shipped config no longer uses TOML tables" \
  "$(grep -c '^\[\[profile\]\]' "$CONF")" "0"
check "and declares its profiles the hyprlang way" \
  "$(grep -cE '^profile \{' "$CONF")" "1"
check "and keeps a commented night profile to enable" \
  "$(grep -cE '^# profile \{' "$CONF")" "1"
check "the fixture of the old file really is the TOML one" \
  "$(grep -c '^\[\[profile\]\]' "$OLD_TOML")" "1"

# --- autostart ---------------------------------------------------------------

code_of() { sed 's/^[[:space:]]*--.*//' "$1"; }
check "autostart starts hyprsunset, so the profiles are read at login" \
  "$(code_of "$REPO/default/hypr/autostart.lua" | grep -c 'uwsm app -- hyprsunset')" "1"
check "stripping comments leaves autostart's code intact" \
  "$(code_of "$REPO/default/hypr/autostart.lua" | grep -c 'uwsm app -- waybar')" "1"

# --- nothing still calls the file TOML ---------------------------------------

check "the README no longer lists hyprsunset.conf among the TOML configs" \
  "$(grep -c 'hyprsunset.conf. are TOML' "$REPO/README.md")" "0"
check "nor does the update script" \
  "$(grep -c 'hyprsunset.conf are TOML' "$REPO/.local/bin/hyprsimple-update.sh")" "0"

# --- hyprsunset's own verdict ------------------------------------------------

if ! command -v hyprsunset >/dev/null 2>&1; then
  pass "hyprsunset is not installed here, so its verdict is skipped"
else
  # XDG_CONFIG_HOME, not HOME: hyprsunset resolves the path without consulting
  # HOME, so pointing HOME elsewhere reads the real user's file instead.
  verdict() {
    local dir="$TMP/xdg-$RANDOM"; mkdir -p "$dir/hypr"
    cp "$1" "$dir/hypr/hyprsunset.conf"
    timeout 4 env XDG_CONFIG_HOME="$dir" hyprsunset >"$dir/out" 2>&1 &
    local pid=$! waited=0
    # Wait for the verdict rather than for a fixed two seconds. Four of these
    # in one suite made the sweep noticeably slower, and a fixed sleep is both
    # slower than it needs to be and flakier than it looks.
    while (( waited < 40 )); do
      grep -q 'Loaded [0-9]* profiles' "$dir/out" 2>/dev/null && break
      sleep 0.1
      waited=$((waited + 1))
    done
    kill "$pid" 2>/dev/null
    pkill -x hyprsunset 2>/dev/null
    wait "$pid" 2>/dev/null
    cat "$dir/out"
  }

  out=$(verdict "$OLD_TOML")
  check "hyprsunset rejects the old TOML file" \
    "$(printf '%s' "$out" | grep -c 'Invalid config line')" "1"
  check "and loads none of its profiles" \
    "$(printf '%s' "$out" | grep -c 'Loaded 0 profiles')" "1"

  out=$(verdict "$CONF")
  check "hyprsunset accepts the new file" \
    "$(printf '%s' "$out" | grep -c 'Config error')" "0"
  check "and loads the day profile from it" \
    "$(printf '%s' "$out" | grep -c 'Loaded 1 profiles')" "1"

  # The commented night profile has to be valid too, or the invitation to
  # uncomment it is the same empty promise in a new syntax.
  sed 's/^# profile {/profile {/; s/^#     time/    time/; s/^#     temperature/    temperature/; s/^# }/}/' \
    "$CONF" >"$TMP/night.conf"
  out=$(verdict "$TMP/night.conf")
  check "uncommenting the night profile is valid too" \
    "$(printf '%s' "$out" | grep -c 'Config error')" "0"
  check "and gives two profiles" \
    "$(printf '%s' "$out" | grep -c 'Loaded 2 profiles')" "1"
fi

# --- the migration -----------------------------------------------------------

mk() {
  rm -rf "${TMP:?}/mhome" "${TMP:?}/minstall"
  mkdir -p "$TMP/mhome/.config/hypr" "$TMP/minstall/.config/hypr"
  cp "$CONF" "$TMP/minstall/.config/hypr/hyprsunset.conf"
  cp "$1" "$TMP/mhome/.config/hypr/hyprsunset.conf"
}
run_migration() {
  HOME="$TMP/mhome" HYPRSIMPLE_PATH="$TMP/minstall" bash "$MIGRATION" >"$TMP/mout" 2>&1
}

sum=$(md5sum "$OLD_TOML" | cut -d' ' -f1)
if grep -q "$sum" "$MIGRATION"; then
  pass "the migration lists the checksum of the file it replaces"
else
  fail "the migration does not list $sum, so it will not update an existing install"
fi

mk "$OLD_TOML"
run_migration
check "an untouched TOML config is replaced" \
  "$(cmp -s "$TMP/mhome/.config/hypr/hyprsunset.conf" "$CONF" && echo yes || echo no)" "yes"
check "and the previous version is kept" \
  "$([[ -f $TMP/mhome/.config/hypr/hyprsunset.conf.bak ]] && echo yes || echo no)" "yes"

run_migration
check "re-running on an already current file says nothing" \
  "$(grep -c 'Updated' "$TMP/mout")" "0"

printf '[[profile]]\nname = "mine"\n' >"$TMP/edited.conf"
mk "$TMP/edited.conf"
run_migration
check "an edited config is left alone" \
  "$(head -1 "$TMP/mhome/.config/hypr/hyprsunset.conf")" '[[profile]]'
check "and the user is told hyprsunset cannot read it" \
  "$(grep -c 'loads no profiles at all' "$TMP/mout")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
