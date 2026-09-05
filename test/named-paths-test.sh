#!/bin/bash
# Two places where hyprsimple named a path that nothing creates.
#
# record-audio.sh wrote to $HOME/Music. install.sh creates ~/Videos and
# ~/Pictures and not ~/Music, and ffmpeg does not create the directory it is
# asked to write into. Measured before the fix, with HOME pointed at an empty
# directory:
#
#   Error opening output .../Music/20260905_130134.wav: No such file or directory
#   exit 254, and no directory created
#
# Its two siblings both handle this. screen-record.sh checks and notifies;
# screenshot.sh delegates to hyprshot, which runs mkdir -p itself. This one did
# neither, and it is the documented way to record audio.
#
# default/hypr/env.lua exported XCOMPOSEFILE=$HOME/.XCompose. Nothing creates
# that file either: upstream writes one in its own install step and only the
# variable was carried over. man 5 Compose gives the search order as
# $XCOMPOSEFILE, then ~/.XCompose, then the locale's system compose file, so
# the home file is already found without being named, and naming a file that is
# not there is what stops the third rule from being reached.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"; mkdir -p "$STUB"
# ffmpeg records nothing here. It reports the directory it was handed, which is
# the whole question, and refuses to write if that directory is missing, which
# is what the real one does.
cat >"$STUB/ffmpeg" <<'STUBEOF'
#!/bin/bash
out="${*: -1}"
printf 'ffmpeg %s\n' "$*" >>"$CALL_LOG"
[[ -d ${out%/*} ]] || { printf 'Error opening output %s: No such file or directory\n' "$out" >&2; exit 254; }
: >"$out"
STUBEOF
chmod +x "$STUB/ffmpeg"

LOG="$TMP/calls"
run_record() {
  rm -rf "${TMP:?}/home"; mkdir -p "$TMP/home"
  : >"$LOG"
  HOME="$TMP/home" CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" \
    ${1:+env XDG_MUSIC_DIR="$1"} bash "$BIN/record-audio.sh" >/dev/null 2>&1
  echo $?
}

# --- record-audio.sh --------------------------------------------------------

rc=$(run_record "")
check "recording into a home with no Music directory now succeeds" "$rc" "0"
check "and the directory was created" \
  "$([[ -d $TMP/home/Music ]] && echo yes || echo no)" "yes"
check "and the file landed in it" \
  "$(find "$TMP/home/Music" -name '*.wav' | wc -l | tr -d ' ')" "1"
check "and ffmpeg was actually invoked" "$(grep -c '^ffmpeg ' "$LOG")" "1"

# The failing shape the fix is for, proven with the stub, so the checks above
# are not passing because the stub is lenient.
mkdir -p "$TMP/probe"
CALL_LOG="$LOG" PATH="$STUB:/usr/bin:/bin" \
  bash -c 'ffmpeg -f alsa -i default "'"$TMP"'/probe/absent/x.wav"' >/dev/null 2>&1
check "the stub does refuse a missing directory, so the fixture is honest" "$?" "254"

# XDG_MUSIC_DIR wins where it is set, which is how the sibling screen-record.sh
# already reads XDG_VIDEOS_DIR.
rc=$(run_record "$TMP/elsewhere")
check "XDG_MUSIC_DIR is honoured" "$rc" "0"
check "and that is where the recording goes" \
  "$(find "$TMP/elsewhere" -name '*.wav' 2>/dev/null | wc -l | tr -d ' ')" "1"
check "and ~/Music is not created when it is not used" \
  "$([[ -d $TMP/home/Music ]] && echo yes || echo no)" "no"

# --- XCOMPOSEFILE ------------------------------------------------------------

# Anchored to the start of a line, because the comment left in env.lua names
# the call it replaced and an unanchored grep counts that too.
lua_call='^[[:space:]]*hl\.env\("XCOMPOSEFILE"'
check "env.lua no longer exports XCOMPOSEFILE" \
  "$(grep -cE "$lua_call" "$REPO/default/hypr/env.lua")" "0"
check "and nothing else in the tree does" \
  "$(grep -rlE "$lua_call" "$REPO/default" "$REPO/.config" 2>/dev/null | wc -l | tr -d ' ')" "0"
# The anchor has to be able to find a real call, or the two checks above pass
# because the pattern is wrong rather than because the line is gone.
printf 'hl.env("XCOMPOSEFILE", "x")\n' >"$TMP/anchor-probe.lua"
check "the anchor does match a real call, so those two mean something" \
  "$(grep -cE "$lua_call" "$TMP/anchor-probe.lua")" "1"

# The file it named is still not shipped, which is the reason the export had to
# go rather than be pointed somewhere else.
check "no .XCompose is shipped, which is why the export was removed" \
  "$(find "$REPO" -name '.XCompose' -not -path '*/.git/*' -not -path '*/external/*' | wc -l | tr -d ' ')" "0"

# env.lua still does its other work, so this is not a check that the file was
# emptied.
check "env.lua still sets xwayland scaling" \
  "$(grep -c 'force_zero_scaling' "$REPO/default/hypr/env.lua")" "1"
check "and still disables the update news" \
  "$(grep -c 'no_update_news' "$REPO/default/hypr/env.lua")" "1"

if command -v lua >/dev/null 2>&1; then
  if lua -e 'local f = loadfile("'"$REPO"'/default/hypr/env.lua"); if f then os.exit(0) else os.exit(1) end'; then
    pass "env.lua still parses as lua"
  else
    fail "env.lua no longer parses as lua"
  fi
fi

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
