#!/bin/bash
# Checks that opening one menu replaces another, and that the clipboard menu no
# longer wipes the clipboard when it is dismissed.
#
# rofi runs one instance at a time through its pid file, so a menu opened while
# another was up did not appear. hyprsimple's own menus pass rofi's -replace,
# and the launcher and power menu scripts, which are the user's, are started
# through hyprsimple-menu-exclusive.sh.
#
# Nothing here opens a menu, touches the clipboard or signals a process this
# suite did not start itself. rofi, cliphist, wl-copy and notify-send are stubs,
# the processes the helper closes are copies of sleep started here, and every
# PATH holds only stubs and the real tools linked in by name.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
HELPER="$BIN/hyprsimple-menu-exclusive.sh"
CLIP="$BIN/hyprsimple-clipboard-menu.sh"
VARS="$REPO/default/hypr/vars.lua"
APPS="$REPO/.config/hypr/bindings/applications.lua"
MIGRATION="$REPO/migrations/1789020000.sh"
TMP="$(mktemp -d)"

# Removes the temp directory and stops every process this suite started, by
# its recorded pid. Never by name: a pattern would match the shell running this.
STARTED=()
trap 'rm -rf "${TMP:?}"; ((${#STARTED[@]})) && kill "${STARTED[@]}" 2>/dev/null' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}
for helper in pass fail check; do
  declare -F "$helper" >/dev/null || { printf 'not ok - helper %s missing\n' "$helper" >&2; exit 1; }
done

BASH_BIN="$(command -v bash)"

# ---- every rofi launch hyprsimple owns passes -replace -------------------------
#
# Read out of the scripts rather than listed here, so a menu added later without
# -replace is caught. Comments are stripped, since several explain -replace in
# prose. A launch is rofi followed by an option or an argument array, which
# leaves out a path ending in /rofi and a pgrep for the process name.

mapfile -t launches < <(
  for f in "$BIN"/*.sh; do
    sed 's/^[[:space:]]*#.*//' "$f" |
      grep -nE '(^|[^-a-zA-Z_/."])rofi +(-|"\$)' |
      sed "s|^|$(basename "$f"):|"
  done
)
if ((${#launches[@]} < 2)); then
  fail "found ${#launches[@]} rofi launches in .local/bin, which is fewer than there are"
else
  pass "found ${#launches[@]} rofi launches in .local/bin"
fi
missing=()
for l in "${launches[@]}"; do
  [[ $l == *-replace* ]] || missing+=("${l%%:*}")
done
check "every one passes -replace" "${missing[*]:-}" ""

for name in show-keybindings.sh hyprsimple-image-picker.sh; do
  check "including $name" "$(printf '%s\n' "${launches[@]}" | grep -c "^$name:")" "1"
done

# ---- the launcher and the power menu are bar panels ----------------------------
#
# vars.lua is evaluated, not grepped, so a quoting slip that leaves the command
# malformed is seen as the string Hyprland would actually run.

LUA=""
for candidate in lua5.4 lua; do
  command -v "$candidate" >/dev/null 2>&1 && { LUA=$candidate; break; }
done
if [[ -n $LUA ]]; then
  # A home under this suite's own temp directory. A literal path under /home
  # is refused by committed-symlinks-test, which keeps any one machine's home
  # out of tracked files.
  LUA_HOME="$TMP/lua-home"
  # The launcher and the power menu are panels of the bar, opened over its ipc.
  # HYPRSIMPLE_PATH is unset for the evaluation so the default install path is
  # what is checked. The launcher still goes through the helper, so a rofi menu
  # that is open is closed first.
  bar_var() {
    env -u HYPRSIMPLE_PATH HOME="$LUA_HOME" "$LUA" -e "local M = dofile('$VARS'); io.write(M.$1)" 2>&1
  }
  check "SUPER + A opens the bar's launcher through the helper" "$(bar_var menu)" \
    "$LUA_HOME/.local/bin/hyprsimple-menu-exclusive.sh qs -p $LUA_HOME/.local/share/hyprsimple/default/quickshell ipc call bar toggle launcher"
  check "and SUPER + ESCAPE opens the bar's power panel" "$(bar_var powermenu)" \
    "qs -p $LUA_HOME/.local/share/hyprsimple/default/quickshell ipc call bar toggle power"
else
  pass "no lua interpreter here, so vars.lua is not evaluated"
fi

# ---- the helper ------------------------------------------------------------------

PROCBIN="$TMP/procbin"; mkdir -p "$PROCBIN"
# A stand-in named rofi, so its process name is rofi and closing it is safe. It
# takes a moment to exit once asked, the way rofi tears down its window. A copy
# of sleep exits the instant it is signalled, and against that a helper that
# never waited passed every check here.
cat >"$PROCBIN/rofi" <<'STANDINEOF'
#!/bin/bash
trap 'sleep 0.3; exit 0' TERM
while :; do sleep 0.05; done
STANDINEOF
chmod +x "$PROCBIN/rofi"
HBIN="$TMP/helperbin"; mkdir -p "$HBIN"
for tool in cat sleep; do ln -sf "$(command -v "$tool")" "$HBIN/$tool"; done
PIDFILE="$TMP/rofi.pid"

# The command the helper runs records whether the old menu was still alive at
# that moment, which is the ordering that matters.
run_helper() {
  local watched="$1"; shift
  : >"$TMP/ran"
  HYPRSIMPLE_ROFI_PIDFILE="$PIDFILE" PATH="$HBIN" \
    "$BASH_BIN" "$HELPER" "$BASH_BIN" -c \
    'if [[ -e /proc/$1 ]]; then echo alive; else echo gone; fi >"$2"; shift 2; printf "%s|" "$@" >>"$0.args"' \
    "$TMP/ran" "$watched" "$TMP/ran" "$@" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

"$PROCBIN/rofi" 30 & open_menu=$!; STARTED+=("$open_menu")
sleep 0.1
check "the stand-in menu really is named rofi" "$(cat "/proc/$open_menu/comm" 2>/dev/null)" "rofi"
printf '%s\n' "$open_menu" >"$PIDFILE"
: >"$TMP/ran.args"
run_helper "$open_menu" "an arg with spaces" second
check "an open menu is closed" "$([[ -e /proc/$open_menu ]] && echo open || echo closed)" "closed"
check "before the new one starts" "$(cat "$TMP/ran")" "gone"
check "and the command runs with its arguments intact" "$(cat "$TMP/ran.args")" "an arg with spaces|second|"

sleep 30 & bystander=$!; STARTED+=("$bystander")
printf '%s\n' "$bystander" >"$PIDFILE"
run_helper "$bystander"
check "a pid file naming a process that is not rofi closes nothing" \
  "$([[ -e /proc/$bystander ]] && echo alive || echo killed)" "alive"
check "and still runs the command" "$(cat "$TMP/ran")" "alive"

"$BASH_BIN" -c 'exit 0' & gone=$!; wait "$gone"
printf '%s\n' "$gone" >"$PIDFILE"
run_helper "$gone"
check "a stale pid file still runs the command" "$(cat "$TMP/ran")" "gone"

printf 'not a pid\n' >"$PIDFILE"
run_helper "$gone"
check "a garbled pid file still runs the command" "$(cat "$TMP/ran")" "gone"

rm -f "$PIDFILE"
run_helper "$gone"
check "no pid file at all still runs the command" "$(cat "$TMP/ran")" "gone"

HYPRSIMPLE_ROFI_PIDFILE="$PIDFILE" PATH="$HBIN" "$BASH_BIN" "$HELPER" >/dev/null 2>&1
check "with no command it only closes and exits 0" "$?" "0"

# ---- the clipboard panel ---------------------------------------------------------
#
# The clipboard history is a panel of the bar. The script behind SUPER + V opens
# it, and the panel copies the picked entry with a short shell command. That
# command is read out of the panel and run here against stand-ins, so what is
# tested is what ships.

PANEL="$REPO/default/quickshell/panels/ClipboardPanel.qml"
COPY_CMD=$(grep -o "'tmp=\$(mktemp).*rm -f \"\$tmp\"'" "$PANEL" | sed "s/^'//; s/'\$//")
check "the panel's copy command was read out of it" \
  "$([[ -n $COPY_CMD ]] && echo read || echo missing)" "read"

CBIN="$TMP/clipbin"; mkdir -p "$CBIN"
for tool in mktemp rm cat; do ln -sf "$(command -v "$tool")" "$CBIN/$tool"; done
printf 'binary\000image\001bytes' >"$TMP/image.bin"

# cliphist decode is given the entry's id, the way the panel calls it.
cat >"$CBIN/cliphist" <<'STUBEOF'
#!/bin/bash
[[ $1 == decode ]] || exit 0
case "$2" in
1) printf 'hello' ;;
2) cat "$IMAGE" ;;
3) exit 1 ;;
4) exit 0 ;;
esac
STUBEOF
# wl-copy records that it ran and exactly what it was given.
cat >"$CBIN/wl-copy" <<'STUBEOF'
#!/bin/bash
cat >"$COPIED"
printf 'called\n' >>"$COPY_CALLS"
STUBEOF
cat >"$CBIN/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUBEOF
chmod +x "$CBIN/cliphist" "$CBIN/wl-copy" "$CBIN/notify-send"

check "the real wl-copy is unreachable from the clipboard PATH" \
  "$(PATH="$CBIN" command -v wl-copy)" "$CBIN/wl-copy"

# Its temporary file goes to a folder of this suite's own, so what it leaves
# behind can be counted.
COPY_TMP="$TMP/copy-tmp"; mkdir -p "$COPY_TMP"
run_copy() {
  : >"$TMP/copy-calls"; rm -f "$TMP/copied"
  IMAGE="$TMP/image.bin" COPIED="$TMP/copied" COPY_CALLS="$TMP/copy-calls" \
    TMPDIR="$COPY_TMP" PATH="$CBIN" "$BASH_BIN" -c "$COPY_CMD" sh "$1" >/dev/null 2>&1
}
calls() { grep -c called "$TMP/copy-calls"; }

# Anti-vacuity: the pipeline the first clipboard menu used, under the same
# stand-ins, really does hand wl-copy nothing when no entry decodes. Without
# this the checks below could pass against stand-ins that never reproduce it.
: >"$TMP/copy-calls"; rm -f "$TMP/copied"
IMAGE="$TMP/image.bin" COPIED="$TMP/copied" COPY_CALLS="$TMP/copy-calls" PATH="$CBIN" \
  "$BASH_BIN" -c 'cliphist decode 4 | wl-copy' >/dev/null 2>&1
check "an unguarded pipeline calls wl-copy with nothing decoded" "$(calls)" "1"
check "and hands it nothing, which is what wiped the clipboard" "$(wc -c <"$TMP/copied" | tr -d ' ')" "0"

run_copy 1
check "picking a text entry copies it" "$(cat "$TMP/copied")" "hello"
check "once" "$(calls)" "1"

run_copy 2
check "picking an image copies its bytes exactly, NULs included" \
  "$(cmp -s "$TMP/image.bin" "$TMP/copied" && echo same || echo differs)" "same"

run_copy 3
check "an entry cliphist can no longer decode does not touch the clipboard" "$(calls)" "0"

run_copy 4
check "nor does one that decodes to nothing" "$(calls)" "0"

check "and the copy command leaves no temporary file behind, whichever way it ended" \
  "$(find "$COPY_TMP" -type f | wc -l | tr -d ' ')" "0"

# The script behind SUPER + V. qs is a stand-in that records what it was asked.
cat >"$CBIN/qs" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$QS_LOG"
STUBEOF
chmod +x "$CBIN/qs"
CLIP_HOME="$TMP/clip-home"; mkdir -p "$CLIP_HOME/.local/bin"
cp "$HELPER" "$CLIP_HOME/.local/bin/"
run_clip() {
  : >"$TMP/qs-log"; : >"$TMP/notify"
  # XDG_CONFIG_HOME is set although nothing here starts rofi any more. The
  # script closes a rofi that is open, and no real config should be in reach.
  QS_LOG="$TMP/qs-log" NOTIFY_LOG="$TMP/notify" HOME="$CLIP_HOME" \
    XDG_CONFIG_HOME="$TMP/xdg" HYPRSIMPLE_ROFI_PIDFILE="$TMP/no-such-pid" \
    PATH="$CBIN" "$BASH_BIN" "$CLIP" >/dev/null 2>&1
}

run_clip
check "SUPER + V opens the bar's clipboard panel" \
  "$(cat "$TMP/qs-log")" "-p $CLIP_HOME/.local/share/hyprsimple/default/quickshell ipc call bar toggle clipboard"
check "through the helper, so an open rofi menu is closed first" \
  "$(sed 's/#.*//' "$CLIP" | grep -c 'hyprsimple-menu-exclusive.sh" qs ')" "1"
check "and the panel answers to that name" \
  "$(grep -c 'name: "clipboard"' "$REPO/default/quickshell/bar/Bar.qml")" "1"

rm "$CBIN/cliphist"
run_clip
check "without cliphist it says so" "$(grep -c 'cliphist is not installed' "$TMP/notify")" "1"
check "and opens nothing" "$(wc -l <"$TMP/qs-log" | tr -d ' ')" "0"

# ---- the migration ---------------------------------------------------------------

OLD_LINE=$(cat <<'LINEEOF'
hl.bind("SUPER + V", hl.dsp.exec_cmd("sh -c 'cliphist list | rofi --show dmenu | cliphist decode | wl-copy'"),  { description = "Clipboard Manager" })
LINEEOF
)
NEW_LINE=$(sed -n '/^NEW=/,/^LINEEOF/p' "$MIGRATION" | sed '1d;$d')

check "the migration's new line is the one shipped to fresh installs" \
  "$(grep -cxF "$NEW_LINE" "$APPS")" "1"
check "and the shipped file no longer has the old one" "$(grep -cxF "$OLD_LINE" "$APPS")" "0"

MBIN="$TMP/migbin"; mkdir -p "$MBIN"
for tool in cat grep mktemp rm; do ln -sf "$(command -v "$tool")" "$MBIN/$tool"; done
app_home() {
  local h="$TMP/apphome-$1"
  mkdir -p "$h/.config/hypr/bindings"
  printf '%s' "$h"
}
run_migration() {
  HOME="$1" PATH="$MBIN" "$BASH_BIN" "$MIGRATION" >"$TMP/mig-out" 2>&1
}

h=$(app_home shipped)
{
  printf -- '-- my own comment\n'
  printf 'hl.bind("SUPER + T", hl.dsp.exec_cmd(vars.terminal), { description = "Terminal" })\n'
  printf '%s\n' "$OLD_LINE"
  printf 'hl.bind("SUPER + Q", hl.dsp.exec_cmd("my-own-thing"), { description = "Mine" })\n'
} >"$h/.config/hypr/bindings/applications.lua"
before_others=$(grep -vxF "$OLD_LINE" "$h/.config/hypr/bindings/applications.lua")
run_migration "$h"
check "the shipped SUPER + V line is replaced" \
  "$(grep -cxF "$NEW_LINE" "$h/.config/hypr/bindings/applications.lua")" "1"
check "and the old one is gone" "$(grep -cxF "$OLD_LINE" "$h/.config/hypr/bindings/applications.lua")" "0"
check "and every other line is exactly as it was" \
  "$(grep -vxF "$NEW_LINE" "$h/.config/hypr/bindings/applications.lua")" "$before_others"

snapshot=$(cat "$h/.config/hypr/bindings/applications.lua")
run_migration "$h"
check "running it again changes nothing" "$(cat "$h/.config/hypr/bindings/applications.lua")" "$snapshot"
check "and says it is already done" "$(grep -c 'already opens' "$TMP/mig-out")" "1"

h=$(app_home edited)
printf 'hl.bind("SUPER + V", hl.dsp.exec_cmd("my-clipboard-thing"), { description = "Mine" })\n' \
  >"$h/.config/hypr/bindings/applications.lua"
snapshot=$(cat "$h/.config/hypr/bindings/applications.lua")
run_migration "$h"
check "a SUPER + V line of your own is left alone" "$(cat "$h/.config/hypr/bindings/applications.lua")" "$snapshot"
check "and the line to use is printed" "$(grep -cF "$NEW_LINE" "$TMP/mig-out")" "1"

h="$TMP/apphome-none"; mkdir -p "$h"
run_migration "$h"
check "a home with no applications.lua gets none" \
  "$([[ -e $h/.config/hypr/bindings/applications.lua ]] && echo created || echo absent)" "absent"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
