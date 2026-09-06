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

# --- and the last thing an install says -------------------------------------
#
# The closing message told every new user
#
#   2. Customize ~/.config/hypr/monitors.conf for your setup
#
# and there has been no monitors.conf since the config became lua. The one
# instruction an installer leaves you with named a file that is not there.
#
# Every ~/.config path the installer names is checked, not just that one, since
# the same drift can happen to any of them. Paths under a directory hyprsimple
# creates rather than ships are exempted by name.

INSTALL="$REPO/install.sh"
# Comments stripped before any of this counts anything. install.sh explains in
# comments what it used to do, naming both the dangling
# ~/.config/rofi/launcher/launcher link it no longer makes and the
# `hyprctl dispatch exit` it no longer runs, and an unanchored grep reads those
# explanations as code. Three of these checks failed that way first.
code_of() { sed 's/#.*//' "$1"; }
INSTALL_CODE="$TMP/install.code"
code_of "$INSTALL" >"$INSTALL_CODE"
check "stripping comments leaves install.sh's code behind" \
  "$(grep -c '^install_packages()' "$INSTALL_CODE")" "1"
GENERATED="uwsm/env uwsm/env-hyprland btop/themes rofi/hyprsimple hypr/hyprsimple
  dunst/dunstrc.d hypr/theme-active.lua hypr/theme-hyprlock.conf"

# Both spellings. install.sh writes "$HOME/.config/..." in code and ~/.config/...
# in the text it prints, and reading only the printed form found a single path,
# which is not enough for the check below to mean anything.
mapfile -t named < <(
  {
    # shellcheck disable=SC2088  # a grep pattern, not a path to expand
    grep -oE '~/\.config/[A-Za-z0-9_./-]+' "$INSTALL_CODE"
    grep -oE '\$HOME/\.config/[A-Za-z0-9_./-]+' "$INSTALL_CODE"
  } | sed 's|~/\.config/||; s|\$HOME/\.config/||; s|[./]*$||' | LC_ALL=C sort -u
)
if (( ${#named[@]} < 3 )); then
  fail "found ${#named[@]} config paths in install.sh, so this is not reading it"
else
  pass "checked ${#named[@]} config paths the installer names"
fi

absent=()
for rel in "${named[@]}"; do
  # Written by the installer or by a theme switch rather than shipped. Matched
  # as a prefix: the exempt entries name directories, and the paths found
  # include files inside them, such as the dunst drop-in symlink.
  exempt=0
  for gen in $GENERATED; do
    [[ $rel == "$gen" || $rel == "$gen"/* ]] && { exempt=1; break; }
  done
  (( exempt )) && continue
  [[ -e $REPO/.config/$rel ]] && continue
  absent+=("$rel")
done
absent_str=""
(( ${#absent[@]} > 0 )) && absent_str="$(printf '%s ' "${absent[@]}")"
check "and every one of them is a file hyprsimple ships" "$absent_str" ""

# The specific one, by name, so the reason stays readable.
check "the closing message names monitors.lua" \
  "$(grep -c 'hypr/monitors.lua for your setup' "$INSTALL_CODE")" "1"
check "and no longer monitors.conf, which has not existed since the lua split" \
  "$(grep -c 'monitors.conf' "$INSTALL_CODE")" "0"

# --- and it leaves the session the way hyprsimple leaves it ------------------
#
# The prompt at the end ran `hyprctl dispatch exit`, which tears the compositor
# down at once. A browser still flushing its profile is killed, which is the
# single thing hypr-logout.sh exists to prevent, and the installer was the last
# place still doing it. It is also the wrong call under uwsm, which wants its
# session stopped rather than its compositor shot.

check "the installer logs out through hyprsimple's own logout" \
  "$(grep -c 'hypr-logout.sh' "$INSTALL_CODE")" "1"
check "and not by shooting the compositor" \
  "$(grep -c 'hyprctl dispatch exit' "$INSTALL_CODE")" "0"
check "and says so rather than erroring when there is no session" \
  "$(grep -c 'pgrep -x Hyprland' "$INSTALL_CODE")" "1"
check "the script it calls is one the installer has already copied" \
  "$([[ -f $BIN/hypr-logout.sh ]] && echo yes || echo no)" "yes"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
