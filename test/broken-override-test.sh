#!/bin/bash
# ~/.config/hypr/hyprland.lua required the six user override files with a bare
# require:
#
#   require("hypr.monitors")
#   require("hypr.bindings.applications")
#   ...
#
# A syntax error in any of them, or a deleted one, aborts the file. Everything
# after that line stops, including the theme overlay at the bottom, which is
# what applies the theme's colours. Measured with a one-character typo in
# windows.lua: the overlay did not load, and nothing said why.
#
# These are files the user is invited to edit, so a syntax error in one is an
# ordinary event rather than an exotic one. default/hypr/vars.lua already loaded
# the user's vars.lua with pcall for this reason, with the reason in a comment
# above it. The entrypoint did not.
#
# Everything here runs in plain lua against the real file, with hl stubbed.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENTRY="$REPO/.config/hypr/hyprland.lua"
MIGRATION="$REPO/migrations/1788627800.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

if ! command -v lua >/dev/null 2>&1; then
  fail "lua is not installed, so none of this suite can run"
  exit 1
fi

# A home with the six override files, a stand-in for the install tree, and a
# theme overlay that records whether it was reached.
build_home() {
  rm -rf "${TMP:?}/fakehome"
  mkdir -p "$TMP/fakehome/.config/hypr/bindings" "$TMP/fakehome/install/default/hypr"
  for m in monitors looknfeel input windows autostart; do
    printf 'return {}\n' >"$TMP/fakehome/.config/hypr/$m.lua"
  done
  printf 'return {}\n' >"$TMP/fakehome/.config/hypr/bindings/applications.lua"
  # The install side only has to be requireable, and to record that it ran.
  printf 'DEFAULTS_LOADED = true\nreturn {}\n' \
    >"$TMP/fakehome/install/default/hypr/hyprsimple.lua"
  # The theme overlay, which the old code could never reach after a failure.
  printf 'THEME_LOADED = true\n' >"$TMP/fakehome/.config/hypr/theme-active.lua"
}

# Runs the real entrypoint with hl stubbed, and prints what happened.
run_entry() {
  cat >"$TMP/run.lua" <<LUAEOF
local calls = {}
hl = {
  on = function(_, fn) table.insert(calls, fn) end,
  exec_cmd = function(cmd) print("EXEC " .. cmd) end,
  config = function() end,
  env = function() end,
  bind = function() end,
  gesture = function() end,
  device = function() end,
  dsp = setmetatable({}, { __index = function() return function() end end }),
}
local ok, err = pcall(dofile, "$ENTRY")
if not ok then print("ENTRYPOINT ABORTED: " .. tostring(err)) end
print("THEME_LOADED=" .. tostring(THEME_LOADED))
print("DEFAULTS_LOADED=" .. tostring(DEFAULTS_LOADED))
-- Anything registered for hyprland.start runs now, which is when the session
-- would report a failure.
for _, fn in ipairs(calls) do fn() end
LUAEOF
  HOME="$TMP/fakehome" HYPRSIMPLE_PATH="$TMP/fakehome/install" \
    lua "$TMP/run.lua" 2>&1
}

# --- everything intact -------------------------------------------------------

build_home
out=$(run_entry)
check "with every override present the theme overlay loads" \
  "$(printf '%s' "$out" | grep -c 'THEME_LOADED=true')" "1"
check "and the install defaults load" \
  "$(printf '%s' "$out" | grep -c 'DEFAULTS_LOADED=true')" "1"
check "and nothing is reported" "$(printf '%s' "$out" | grep -c 'did not load')" "0"

# --- a syntax error in one override -----------------------------------------

build_home
printf 'local x = {\n' >"$TMP/fakehome/.config/hypr/windows.lua"
out=$(run_entry)
check "a typo in one override no longer aborts the entrypoint" \
  "$(printf '%s' "$out" | grep -c 'ENTRYPOINT ABORTED')" "0"
check "and the theme overlay still loads" \
  "$(printf '%s' "$out" | grep -c 'THEME_LOADED=true')" "1"
check "and the failure is reported once" \
  "$(printf '%s' "$out" | grep -c 'did not load')" "1"
check "and the report names the file" \
  "$(printf '%s' "$out" | grep -c 'windows.lua')" "1"

# --- a deleted override ------------------------------------------------------

build_home
rm "$TMP/fakehome/.config/hypr/windows.lua"
out=$(run_entry)
check "a deleted override does not abort the entrypoint either" \
  "$(printf '%s' "$out" | grep -c 'ENTRYPOINT ABORTED')" "0"
check "and the theme overlay still loads" \
  "$(printf '%s' "$out" | grep -c 'THEME_LOADED=true')" "1"
check "and it is reported" "$(printf '%s' "$out" | grep -c 'did not load')" "1"

# --- more than one broken at a time -----------------------------------------

build_home
printf 'local x = {\n' >"$TMP/fakehome/.config/hypr/windows.lua"
rm "$TMP/fakehome/.config/hypr/input.lua"
out=$(run_entry)
check "two broken overrides are both reported" \
  "$(printf '%s' "$out" | grep -c 'did not load')" "2"
check "and the theme overlay still loads" \
  "$(printf '%s' "$out" | grep -c 'THEME_LOADED=true')" "1"

# A single quote in the error text must not break the shell command the report
# is built into.
build_home
printf "local x = 'unterminated\n" >"$TMP/fakehome/.config/hypr/windows.lua"
out=$(run_entry)
check "an error containing a quote produces a single-quoted command" \
  "$(printf '%s' "$out" | grep -c "^EXEC notify-send -u critical 'hyprsimple: a config file did not load' '")" "1"
check "and no stray quote survives in the message" \
  "$(printf '%s' "$out" | grep 'did not load' | tr -cd "'" | wc -c | tr -d ' ')" "4"

# --- the migration -----------------------------------------------------------

mk_migration_home() {
  rm -rf "${TMP:?}/mhome" "${TMP:?}/minstall"
  mkdir -p "$TMP/mhome/.config/hypr" "$TMP/minstall/.config/hypr"
  cp "$ENTRY" "$TMP/minstall/.config/hypr/hyprland.lua"
  printf '%s' "$1" >"$TMP/mhome/.config/hypr/hyprland.lua"
}
mk_migration_home_from_file() {
  rm -rf "${TMP:?}/mhome" "${TMP:?}/minstall"
  mkdir -p "$TMP/mhome/.config/hypr" "$TMP/minstall/.config/hypr"
  cp "$ENTRY" "$TMP/minstall/.config/hypr/hyprland.lua"
  cp "$1" "$TMP/mhome/.config/hypr/hyprland.lua"
}
run_migration() {
  HOME="$TMP/mhome" HYPRSIMPLE_PATH="$TMP/minstall" \
    bash "$MIGRATION" >"$TMP/mout" 2>&1
}

# The version this replaces, as a committed fixture. Not read from git history:
# CI checks out shallow, so `git show HEAD:` there hands back the current file
# and the migration check would compare it against itself and pass.
PREV="$REPO/test/fixtures/hypr/hyprland.lua.pre-softload"
if [[ ! -s $PREV ]]; then
  fail "the pre-fix fixture is missing, so the migration is untested"
else
  prev_sum=$(md5sum "$PREV" | cut -d' ' -f1)
  if cmp -s "$PREV" "$ENTRY"; then
    fail "the fixture is identical to the current entrypoint, so it is not a previous version"
  else
    pass "the fixture differs from the current entrypoint, as a previous version must"
  fi
  if grep -q "$prev_sum" "$MIGRATION"; then
    pass "the migration lists the checksum of the version it replaces"
  else
    fail "the migration does not list $prev_sum, so it will not update an existing install"
  fi

  mk_migration_home_from_file "$PREV"
  run_migration
  check "an untouched entrypoint is replaced" \
    "$(cmp -s "$TMP/mhome/.config/hypr/hyprland.lua" "$ENTRY" && echo yes || echo no)" "yes"
  check "and the previous version is kept" \
    "$([[ -f $TMP/mhome/.config/hypr/hyprland.lua.bak ]] && echo yes || echo no)" "yes"

  run_migration
  check "re-running on an already current file says nothing" \
    "$(grep -c 'Updated' "$TMP/mout")" "0"
fi

mk_migration_home "-- my own entrypoint
require('hypr.monitors')
"
run_migration
check "an edited entrypoint is left alone" \
  "$(head -1 "$TMP/mhome/.config/hypr/hyprland.lua")" "-- my own entrypoint"
check "and the user is told how to take the new one" \
  "$(grep -c 'hyprsimple-refresh-config.sh hypr/hyprland.lua' "$TMP/mout")" "1"
check "and no backup is written, nothing having changed" \
  "$([[ -f $TMP/mhome/.config/hypr/hyprland.lua.bak ]] && echo yes || echo no)" "no"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
