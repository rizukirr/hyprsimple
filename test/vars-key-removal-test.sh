#!/bin/bash
# default/hypr/vars.lua is install-owned and arrives on the next update.
# ~/.config/hypr/bindings/applications.lua is user-owned and does not. Removing
# a key from the first while the second still reads it is therefore a breaking
# change, and #62 shipped one: exec_cmd raised "expected string, got nil" and
# Hyprland rejected the entire config rather than the two offending lines.
#
# Two things are pinned here. An unknown key answers with a command instead of
# nil, so an out-of-date bindings file loses one key rather than all of them.
# And the migration replaces a bindings file that was never edited, so the
# common case gets the real fix rather than the fallback.

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

VARS="$REPO/default/hypr/vars.lua"

# ---- the fallback -------------------------------------------------------

check "a key vars.lua does set returns its value" \
  "$(lua -e "io.write(dofile('$VARS').terminal)")" "ghostty"

check "a key vars.lua does not set returns a string, not nil" \
  "$(lua -e "io.write(type(dofile('$VARS').notAKeyAnyoneShips))")" "string"

# The string has to be a command, because that is what exec_cmd will run. A
# fallback that returns a bare message would be handed to the shell as one.
fallback="$(lua -e "io.write(dofile('$VARS').notes)")"
check "the fallback names the missing key" \
  "$(printf '%s' "$fallback" | grep -c 'vars\.notes')" "1"

# Running it under a stub, rather than asking whether it parses. Every string
# parses as a shell command, including a bare message, so a parse check passes
# on a fallback that only prints "command not found" at the user.
STUB="$TMP/bin"
mkdir -p "$STUB"
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$@" >>"$NOTIFY_LOG"
STUBEOF
chmod +x "$STUB/notify-send"

NOTIFY_LOG="$TMP/notify.log"
: >"$NOTIFY_LOG"
NOTIFY_LOG="$NOTIFY_LOG" PATH="$STUB:$PATH" sh -c "$fallback"
check "the fallback actually notifies when run" \
  "$(grep -c 'vars\.notes' "$NOTIFY_LOG")" "1"
check "the notification says where to set it" \
  "$(grep -c 'applications\.lua' "$NOTIFY_LOG")" "1"

# ---- every vars key the shipped config reads is actually set -------------

mapfile -t referenced < <(
  grep -rhoE '\bvars\.[a-zA-Z][a-zA-Z0-9]*' \
    "$REPO/.config/hypr/bindings"/*.lua \
    "$REPO/default/hypr/autostart.lua" \
    "$REPO/default/hypr/bindings"/*.lua 2>/dev/null |
    sed 's/^vars\.//' | sort -u
)

check "the extractor found vars keys in the shipped config" \
  "$([[ ${#referenced[@]} -ge 3 ]] && echo enough || echo "only ${#referenced[@]}")" "enough"

for key in "${referenced[@]}"; do
  if grep -qE "^M\.$key = " "$VARS"; then
    pass "vars.$key is set in default/hypr/vars.lua"
  else
    fail "vars.$key is read by the shipped config but default/hypr/vars.lua does not set it"
  fi
done

# ---- the migration ------------------------------------------------------

# A glob rather than parsing ls, which is the finding class this project has
# actually shipped as a bug. Migrations are named after a unix timestamp, so
# the glob's own sort is chronological.
migrations=("$REPO/migrations"/*.sh)
MIGRATION="${migrations[-1]}"
if grep -q 'applications.lua' "$MIGRATION"; then
  pass "the newest migration is the applications.lua one"
else
  fail "the newest migration does not mention applications.lua, so this suite is aimed at the wrong file"
fi

SHIPPED="$REPO/.config/hypr/bindings/applications.lua"

# The version users had before #62, kept as a fixture rather than read from git
# history, because CI checks out shallow and the commit is not there.
#
# A fixture can rot into something no user ever had, so it is checked against
# the migration's own checksum list rather than trusted. If those disagree,
# every case below is testing bytes that do not matter.
PREVIOUS="$REPO/test/fixtures/applications.lua.pre-62"
previous_sum="$(md5sum "$PREVIOUS" | cut -d' ' -f1)"
check "the fixture is a version the migration claims to handle" \
  "$(grep -c "$previous_sum" "$MIGRATION")" "1"

if [[ ! -s $PREVIOUS ]]; then
  fail "the pre-#62 applications.lua fixture is missing"
else
  run_migration() {
    local home="$1"
    HOME="$home" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" 2>&1
  }

  # pristine: replaced, with a backup
  home_pristine="$TMP/pristine"
  mkdir -p "$home_pristine/.config/hypr/bindings"
  cp "$PREVIOUS" "$home_pristine/.config/hypr/bindings/applications.lua"
  run_migration "$home_pristine" >/dev/null
  check "a never-edited bindings file is replaced with the shipped one" \
    "$(cmp -s "$home_pristine/.config/hypr/bindings/applications.lua" "$SHIPPED" && echo replaced || echo unchanged)" \
    "replaced"
  check "the replaced file is backed up" \
    "$(cmp -s "$home_pristine/.config/hypr/bindings/applications.lua.bak" "$PREVIOUS" && echo kept || echo lost)" \
    "kept"

  # edited: untouched
  home_edited="$TMP/edited"
  mkdir -p "$home_edited/.config/hypr/bindings"
  { cat "$PREVIOUS"; printf '\n-- MY OWN BINDING MARKER\n'; } >"$home_edited/.config/hypr/bindings/applications.lua"
  out="$(run_migration "$home_edited")"
  check "an edited bindings file is left alone" \
    "$(grep -c 'MY OWN BINDING MARKER' "$home_edited/.config/hypr/bindings/applications.lua")" "1"
  check "an edited bindings file gets no backup, because nothing was replaced" \
    "$([[ -f $home_edited/.config/hypr/bindings/applications.lua.bak ]] && echo yes || echo no)" "no"
  check "the user is told how to take hyprsimple's version" \
    "$(printf '%s' "$out" | grep -c 'hyprsimple-refresh-config.sh hypr/bindings/applications.lua')" "1"

  # already current: no-op, and no stray backup
  home_current="$TMP/current"
  mkdir -p "$home_current/.config/hypr/bindings"
  cp "$SHIPPED" "$home_current/.config/hypr/bindings/applications.lua"
  out_current="$(run_migration "$home_current")"
  check "an already-current bindings file is a no-op" \
    "$([[ -f $home_current/.config/hypr/bindings/applications.lua.bak ]] && echo backed-up || echo untouched)" \
    "untouched"
  # Without the early cmp, a file that is already current falls through to the
  # unknown-checksum branch and every future update tells the user they have
  # edits they do not have.
  check "an already-current bindings file is not accused of having edits" \
    "$(printf '%s' "$out_current" | grep -c 'your own edits')" "0"

  # re-running the migration must not undo the first run
  run_migration "$home_pristine" >/dev/null
  check "re-running the migration changes nothing" \
    "$(cmp -s "$home_pristine/.config/hypr/bindings/applications.lua" "$SHIPPED" && echo still-current || echo drifted)" \
    "still-current"
fi

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
