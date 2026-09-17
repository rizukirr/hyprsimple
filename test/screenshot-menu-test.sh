#!/bin/bash
# Checks the screenshot menu behind Print.
#
# There were four keybinds, three of them chords, and a region could be saved but
# never copied. This is one key and a list of six: region, window or whole
# screen, each saved or copied.
#
# Nothing here opens a menu or takes a screenshot. rofi, notify-send and hyprshot
# are stubs, screenshot.sh is replaced by a stub when the menu is driven, and the
# PATH each run gets holds only the stubs plus the two real tools linked in by
# name. /usr/bin is never on it: a probe that left it there once ran a real
# command on the maintainer's machine.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
MENU="$BIN/hyprsimple-screenshot-menu.sh"
SHOOTER="$BIN/screenshot.sh"
STYLE="$REPO/default/rofi/screenshot/style.rasi"
STUB_STYLE="$REPO/.config/rofi/screenshot/style.rasi"
BINDS="$REPO/default/hypr/bindings/screenshot.lua"
MIGRATION="$REPO/migrations/1788990000.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

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
STUB="$TMP/bin"; mkdir -p "$STUB"
HOME_DIR="$TMP/home"; mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/rofi/screenshot"

# The real tools linked in by name: sleep for the pause the menu takes before
# capturing, and cat, which the rofi stub below uses to record its input.
for tool in sleep cat; do ln -sf "$(command -v "$tool")" "$STUB/$tool"; done

# rofi records what it was fed and answers with whatever the test chose. The
# real one would open a menu on the screen of whoever runs the suite.
cat >"$STUB/rofi" <<'STUBEOF'
#!/bin/bash
cat >"$ROFI_INPUT"
printf '%s' "$*" >"$ROFI_ARGS"
printf '%s' "${ROFI_PICK:-}"
STUBEOF
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUBEOF
cat >"$STUB/hyprshot" <<'STUBEOF'
#!/bin/bash
printf 'hyprshot %s\n' "$*" >>"$SHOT_LOG"
STUBEOF
cat >"$HOME_DIR/.local/bin/screenshot.sh" <<'STUBEOF'
#!/bin/bash
printf 'screenshot.sh %s\n' "$*" >>"$SHOT_LOG"
STUBEOF
chmod +x "$STUB"/rofi "$STUB"/notify-send "$STUB"/hyprshot "$HOME_DIR/.local/bin/screenshot.sh"
cp "$MENU" "$HOME_DIR/.local/bin/"
cp "$STUB_STYLE" "$HOME_DIR/.config/rofi/screenshot/style.rasi"

INPUT="$TMP/menu-input"; ARGS="$TMP/rofi-args"
LOG="$TMP/shots"; NLOG="$TMP/notifications"

open_menu() {
  : >"$LOG"; : >"$NLOG"; : >"$INPUT"; : >"$ARGS"
  ROFI_INPUT="$INPUT" ROFI_ARGS="$ARGS" ROFI_PICK="${1-}" \
    SHOT_LOG="$LOG" NOTIFY_LOG="$NLOG" HOME="$HOME_DIR" \
    HYPRSIMPLE_SCREENSHOT_MENU_SETTLE=0 PATH="$STUB" \
    "$BASH_BIN" "$HOME_DIR/.local/bin/hyprsimple-screenshot-menu.sh" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

# ---- anti-vacuity, before anything rests on the stubs -----------------------

check "the real rofi is unreachable from the restricted PATH" \
  "$(PATH="$STUB" command -v rofi)" "$STUB/rofi"
check "and so is the real hyprshot" \
  "$(PATH="$STUB" command -v hyprshot)" "$STUB/hyprshot"

# ---- one key, not four -------------------------------------------------------

lua_code() { sed 's/^[[:space:]]*--.*//' "$BINDS" | tr '\n' ' '; }
check "there is one screenshot keybind" "$(lua_code | grep -o 'hl.bind(' | wc -l | tr -d ' ')" "1"
check "and it is Print" "$(lua_code | grep -c 'hl.bind("Print"')" "1"
check "and it opens the menu rather than taking a screenshot" \
  "$(lua_code | grep -c 'hyprsimple-screenshot-menu.sh')" "1"
check "so no bind passes a mode itself any more" \
  "$(lua_code | grep -c 'screenshot.sh ')" "0"

# ---- the six entries, chosen by index ----------------------------------------
#
# Each entry is picked in turn and the mode read back. The mapping is the whole
# point of the menu, so every row is exercised.

declare -a expected=(region region-clipboard window window-clipboard monitor clipboard)

open_menu 0
check "the menu offers six ways to take a screenshot" "$(wc -l <"$INPUT" | tr -d ' ')" "6"

wrong=()
for i in "${!expected[@]}"; do
  open_menu "$i"
  got=$(sed 's/^screenshot.sh //' "$LOG")
  [[ $got == "${expected[$i]}" ]] || wrong+=("$i wanted '${expected[$i]}' got '$got'")
done
wrong_str=""; ((${#wrong[@]} > 0)) && wrong_str="$(printf '%s; ' "${wrong[@]}")"
check "every entry runs the mode it names" "$wrong_str" ""

# The label and the mode have to agree, not just the index and the mode. Read
# out of the script: an entry saying clipboard must run a mode that copies, and
# one saying region must run a mode that captures a region.
mismatch=$(python3 - "$MENU" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
labels = re.findall(r'"([^"]+)"', re.search(r'labels=\((.*?)\n\)', src, re.S).group(1))
modes = re.search(r'modes=\((.*?)\n\)', src, re.S).group(1).split()
bad = []
if len(labels) != len(modes):
    bad.append(f"{len(labels)} labels for {len(modes)} modes")
for label, mode in zip(labels, modes):
    copies = "clipboard" in mode
    if ("clipboard" in label) != copies:
        bad.append(f"{label!r} runs {mode}")
    for word, want in (("Region", "region"), ("Window", "window")):
        if word in label and want not in mode:
            bad.append(f"{label!r} runs {mode}")
    if "Whole screen" in label and mode not in ("monitor", "clipboard"):
        bad.append(f"{label!r} runs {mode}")
print("; ".join(bad))
PYEOF
)
check "every label describes the mode it runs" "$mismatch" ""

open_menu 0
check "the menu names region, window and whole screen" \
  "$(grep -cE 'Region|Window|Whole screen' "$INPUT")" "6"
check "and says where each one goes" \
  "$(grep -cE 'save to file|copy to clipboard' "$INPUT")" "6"

# Every entry begins with a real icon, read out of the file rather than the
# rofi input, so a glyph lost on the way into the script is caught here.
glyph_report=$(python3 - "$MENU" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
labels = re.findall(r'"([^"]+)"', re.search(r'labels=\((.*?)\n\)', src, re.S).group(1))
if len(labels) < 6:
    print(f"only {len(labels)} labels found")
    raise SystemExit(0)
def pua(c): return 0xE000 <= ord(c) <= 0xF8FF or 0xF0000 <= ord(c) <= 0xFFFFD
bad = [l for l in labels if not l or not pua(l[0])]
print("blank: " + ", ".join(repr(l) for l in bad) if bad else "all glyphed")
PYEOF
)
check "every menu entry starts with an icon" "$glyph_report" "all glyphed"

codepoints=$(python3 - "$MENU" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
labels = re.findall(r'"([^"]+)"', re.search(r'labels=\((.*?)\n\)', src, re.S).group(1))
seen = {}
for l in labels:
    kind = l[1:].strip().split(",")[0]
    seen.setdefault(kind, f"{ord(l[0]):05X}")
print(" ".join(seen[k] for k in ("Region", "Window", "Whole screen") if k in seen))
PYEOF
)
read -r region_cp window_cp screen_cp <<<"$codepoints"
check "region, window and screen each have their own icon" \
  "$(printf '%s\n' "$region_cp" "$window_cp" "$screen_cp" | sort -u | grep -c .)" "3"

menu_font=$(grep -oE 'font: *"[^"]+"' "$STYLE" | head -1 | sed 's/.*"\(.*\)"/\1/')
menu_family="${menu_font%% [0-9]*}"
installed_families=""
if command -v fc-list >/dev/null 2>&1; then
  installed_families=$(fc-list -f '%{family[0]}\n' 2>/dev/null)
fi
# Skipped where the font itself is absent, which is a CI runner. Captured before
# searching rather than piped into grep -q, which kills fc-list with SIGPIPE
# under pipefail and reads every icon as uncovered.
if [[ -n $menu_family ]] && grep -qiF "$menu_family" <<<"$installed_families"; then
  uncovered=()
  for cp in "$region_cp" "$window_cp" "$screen_cp"; do
    families=$(fc-list -f '%{family[0]}\n' ":charset=$cp" 2>/dev/null)
    grep -qiF "$menu_family" <<<"$families" || uncovered+=("U+$cp")
  done
  uncovered_str=""; ((${#uncovered[@]} > 0)) && uncovered_str="$(printf '%s ' "${uncovered[@]}")"
  check "and the menu's font covers all three icons" "$uncovered_str" ""
else
  pass "the menu's font is not installed here, so icon coverage is not checked"
fi

# ---- answers that are not an index are refused -------------------------------

open_menu "Region, save to file"
check "a label instead of an index captures nothing" "$(wc -c <"$LOG" | tr -d ' ')" "0"
check "and says so" "$(grep -c 'something unexpected' "$NLOG")" "1"
check "and exits non-zero" "$([[ $(cat "$TMP/rc") != 0 ]] && echo failed || echo succeeded)" "failed"

open_menu 6
check "an index past the end of the list captures nothing" "$(wc -c <"$LOG" | tr -d ' ')" "0"
check "and says so too" "$(grep -c 'something unexpected' "$NLOG")" "1"

open_menu ""
check "dismissing the menu captures nothing" "$(wc -c <"$LOG" | tr -d ' ')" "0"
check "and says nothing" "$(wc -c <"$NLOG" | tr -d ' ')" "0"
check "and exits 0" "$(cat "$TMP/rc")" "0"

# ---- a missing screenshot.sh is reported, not silently ignored ----------------

mv "$HOME_DIR/.local/bin/screenshot.sh" "$TMP/shooter.bak"
open_menu 0
check "without screenshot.sh the menu does not open" "$(wc -c <"$ARGS" | tr -d ' ')" "0"
check "and says what to run" "$(grep -c 'Run hyprsimple-update' "$NLOG")" "1"
mv "$TMP/shooter.bak" "$HOME_DIR/.local/bin/screenshot.sh"

# ---- it waits for the menu to be gone, not for a guessed moment -------------
#
# The capture used to wait a fixed 0.2 seconds. rofi's layer closes with the
# slower of layersOut, which inherits global at speed 8, and fadeLayersOut,
# which inherits fade at speed 5, in tenths of a second. hyprshot freezes the
# screen before the selection, so the menu could still be in the shot.
#
# These runs use their own PATH. hyprctl answers from fixtures, and sleep logs
# its argument instead of sleeping, so every wait is read back as a number and
# the suite spends no time waiting.

unset HYPRSIMPLE_SCREENSHOT_MENU_SETTLE
WAIT="$TMP/waitbin"; mkdir -p "$WAIT"
cp "$STUB/rofi" "$STUB/notify-send" "$WAIT/"
for tool in cat jq; do ln -sf "$(command -v "$tool")" "$WAIT/$tool"; done
cat >"$WAIT/sleep" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$1" >>"$SLEEP_LOG"
STUBEOF
# layers lists rofi for as many calls as ROFI_LINGER says, then a screen without
# it. animations is whatever fixture the case wrote.
cat >"$WAIT/hyprctl" <<'STUBEOF'
#!/bin/bash
case "$1" in
layers)
  n=$(cat "$LAYER_COUNT"); n=$((n + 1)); printf '%s' "$n" >"$LAYER_COUNT"
  if ((n <= ROFI_LINGER)); then
    printf '{"eDP-1":{"levels":{"0":[{"namespace":"hyprpaper"}],"2":[{"namespace":"waybar"}],"3":[{"namespace":"rofi"}]}}}'
  else
    printf '{"eDP-1":{"levels":{"0":[{"namespace":"hyprpaper"}],"2":[{"namespace":"waybar"}],"3":[]}}}'
  fi
  ;;
animations)
  cat "$ANIMATIONS"
  ;;
esac
STUBEOF
chmod +x "$WAIT/sleep" "$WAIT/hyprctl"

check "the waiting runs reach the stub hyprctl, not the compositor" \
  "$(PATH="$WAIT" command -v hyprctl)" "$WAIT/hyprctl"
check "and the stub sleep, not a real one" \
  "$(PATH="$WAIT" command -v sleep)" "$WAIT/sleep"

# The shape hyprctl animations -j prints: animations first, beziers second. A
# node that is not overridden reports speed 0 and inherits its parent's.
animations() {
  local global="$1" fade="$2" fade_on="$3" layers_out="$4" layers_out_on="$5"
  local lo_over=false
  [[ $layers_out != - ]] && lo_over=true
  [[ $layers_out == - ]] && layers_out=0
  cat >"$TMP/animations.json" <<JSONEOF
[[
  {"name":"global","overridden":true,"bezier":"default","enabled":true,"speed":$global,"style":""},
  {"name":"fade","overridden":true,"bezier":"default","enabled":$fade_on,"speed":$fade,"style":""},
  {"name":"fadeLayers","overridden":false,"bezier":"","enabled":true,"speed":0,"style":""},
  {"name":"fadeLayersOut","overridden":false,"bezier":"","enabled":true,"speed":0,"style":""},
  {"name":"layers","overridden":false,"bezier":"","enabled":true,"speed":0,"style":""},
  {"name":"layersOut","overridden":$lo_over,"bezier":"","enabled":$layers_out_on,"speed":$layers_out,"style":""}
],[]]
JSONEOF
}

open_menu_waiting() {
  local pick="$1" linger="$2" path="${3:-$WAIT}"
  : >"$LOG"; : >"$NLOG"; : >"$TMP/sleeps"; printf '0' >"$TMP/layer-count"
  ROFI_INPUT="$INPUT" ROFI_ARGS="$ARGS" ROFI_PICK="$pick" \
    SHOT_LOG="$LOG" NOTIFY_LOG="$NLOG" HOME="$HOME_DIR" \
    SLEEP_LOG="$TMP/sleeps" LAYER_COUNT="$TMP/layer-count" ROFI_LINGER="$linger" \
    ANIMATIONS="$TMP/animations.json" PATH="$path" \
    "$BASH_BIN" "$HOME_DIR/.local/bin/hyprsimple-screenshot-menu.sh" >/dev/null 2>&1
}
polls() { grep -cx '0.05' "$TMP/sleeps"; }
close_wait() { grep -vx '0.05' "$TMP/sleeps" | tail -1; }

# hyprsimple's own settings: global 8, fade 5, nothing overridden below them.
animations 8 5 true - true
open_menu_waiting 0 3
check "while rofi is still listed as a layer, the menu keeps waiting" "$(polls)" "3"
check "and asks the compositor again after each wait" "$(cat "$TMP/layer-count")" "4"
check "then waits out the slower close animation, 0.8 seconds, not 0.2" "$(close_wait)" "0.8"
check "and only then takes the screenshot" "$(sed 's/^screenshot.sh //' "$LOG")" "region"

# A config that makes the layer slide faster than it fades.
animations 8 5 true 2 true
open_menu_waiting 0 0
check "a faster layersOut leaves the fade as the slower one, 0.5 seconds" "$(close_wait)" "0.5"
check "with no polling when rofi is already gone" "$(polls)" "0"

animations 8 5 false 2 false
open_menu_waiting 0 0
check "with both close animations disabled it waits no time" "$(close_wait)" "0"

animations 60 50 true - true
open_menu_waiting 0 0
check "an absurdly slow animation is capped at two seconds" "$(close_wait)" "2"

# A layer that never goes must not stop the screenshot for good.
animations 8 5 true - true
open_menu_waiting 0 1000
check "a rofi layer that never goes is polled at most twenty times" "$(polls)" "20"
check "and the screenshot is still taken" "$(sed 's/^screenshot.sh //' "$LOG")" "region"

# Not on Hyprland: no hyprctl to ask.
NOHYPR="$TMP/nohyprbin"; mkdir -p "$NOHYPR"
cp "$WAIT/rofi" "$WAIT/notify-send" "$WAIT/sleep" "$NOHYPR/"
ln -sf "$(command -v cat)" "$NOHYPR/cat"
open_menu_waiting 0 0 "$NOHYPR"
check "without hyprctl it falls back to one second" "$(cat "$TMP/sleeps")" "1"
check "and still takes the screenshot" "$(sed 's/^screenshot.sh //' "$LOG")" "region"

# hyprctl answering garbage reads as no answer rather than a zero wait.
printf 'not json\n' >"$TMP/animations.json"
open_menu_waiting 0 0
check "an animations answer that is not json falls back to one second" "$(close_wait)" "1"

# An explicit pause is used as given, and the compositor is not asked at all.
animations 8 5 true - true
: >"$LOG"; : >"$TMP/sleeps"; printf '0' >"$TMP/layer-count"
ROFI_INPUT="$INPUT" ROFI_ARGS="$ARGS" ROFI_PICK=0 SHOT_LOG="$LOG" NOTIFY_LOG="$NLOG" \
  HOME="$HOME_DIR" SLEEP_LOG="$TMP/sleeps" LAYER_COUNT="$TMP/layer-count" ROFI_LINGER=5 \
  ANIMATIONS="$TMP/animations.json" HYPRSIMPLE_SCREENSHOT_MENU_SETTLE=0.3 PATH="$WAIT" \
  "$BASH_BIN" "$HOME_DIR/.local/bin/hyprsimple-screenshot-menu.sh" >/dev/null 2>&1
check "HYPRSIMPLE_SCREENSHOT_MENU_SETTLE is used as given" "$(cat "$TMP/sleeps")" "0.3"
check "without asking the compositor anything" "$(cat "$TMP/layer-count")" "0"

# Dismissing the menu takes no screenshot, so there is nothing to wait for.
open_menu_waiting "" 3
check "dismissing the menu waits for nothing" "$(wc -c <"$TMP/sleeps" | tr -d ' ')" "0"
check "and asks the compositor nothing" "$(cat "$TMP/layer-count")" "0"

# ---- it asks rofi for the themed style ---------------------------------------

open_menu 0
check "the menu is drawn with the screenshot style, not rofi's default" \
  "$(grep -c -- '-theme .*/.config/rofi/screenshot/style.rasi' "$ARGS")" "1"
check "and asks for an index rather than the line it displayed" \
  "$(grep -c -- '-format i' "$ARGS")" "1"

# ---- the two new modes in screenshot.sh --------------------------------------
#
# Run for real against a stubbed hyprshot, so these are the flags the script
# passes rather than a reading of its source.

run_shooter() {
  : >"$LOG"; : >"$NLOG"
  SHOT_LOG="$LOG" NOTIFY_LOG="$NLOG" HOME="$HOME_DIR" PATH="$STUB" \
    "$BASH_BIN" "$SHOOTER" "$1" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

run_shooter region-clipboard
check "region-clipboard selects a region" "$(grep -c -- '-m region' "$LOG")" "1"
check "and copies it without saving a file" "$(grep -c -- '--clipboard-only' "$LOG")" "1"
check "and silences hyprshot so it is announced once" "$(grep -c -- '--silent' "$LOG")" "1"
check "and announces it" "$(grep -c 'Region copied to clipboard' "$NLOG")" "1"

run_shooter window-clipboard
check "window-clipboard selects a window" "$(grep -c -- '-m window' "$LOG")" "1"
check "and copies it without saving a file" "$(grep -c -- '--clipboard-only' "$LOG")" "1"
check "and announces it" "$(grep -c 'Window copied to clipboard' "$NLOG")" "1"

run_shooter clipboard
check "the old clipboard mode still copies the whole screen" "$(grep -c -- '-m output --clipboard-only' "$LOG")" "1"

run_shooter no-such-mode
check "an unknown mode still captures nothing" "$(wc -c <"$LOG" | tr -d ' ')" "0"
check "and fails" "$([[ $(cat "$TMP/rc") != 0 ]] && echo failed || echo succeeded)" "failed"

# ---- the style follows the theme --------------------------------------------

style_code() { python3 -c "
import re, sys
print(re.sub(r'/\*.*?\*/', '', open(sys.argv[1]).read(), flags=re.S))
" "$STYLE"; }

check "the style imports the theme's palette" "$(style_code | grep -c 'rofi-colors.rasi')" "1"
check "and hard codes no colour of its own" "$(style_code | grep -cE '#[0-9A-Fa-f]{3,8}')" "0"
check "while still setting the colours it needs, from that palette" \
  "$([[ $(style_code | grep -cE '@(background|foreground|selected|background-alt)') -ge 8 ]] && echo enough || echo few)" "enough"
check "and fits all six entries" "$(style_code | grep -cE 'lines: +6;')" "1"
check "the user's stub imports the shipped style" \
  "$(grep -c '@import "hyprsimple/screenshot/style.rasi"' "$STUB_STYLE")" "1"

# rofi -dump-theme reads a theme and prints it without opening a window. HOME and
# XDG_CONFIG_HOME point at a fixture palette so the import cannot resolve against
# the maintainer's real one.
ROFI_HOME="$TMP/rofihome"
mkdir -p "$ROFI_HOME/.config/rofi"
cat >"$ROFI_HOME/.config/rofi/rofi-colors.rasi" <<'PALETTEEOF'
* {
    background:     #11223344;
    background-tr:  #11223322;
    background-alt: #55667788;
    foreground:     #99aabbFF;
    selected:       #ccddeeFF;
    active:         #ccddeeFF;
    urgent:         #ccddeeFF;
}
PALETTEEOF

if command -v rofi >/dev/null 2>&1; then
  if HOME="$ROFI_HOME" XDG_CONFIG_HOME="$ROFI_HOME/.config" \
     rofi -dump-theme -theme "$STYLE" >"$TMP/dump" 2>"$TMP/dumperr"; then
    pass "rofi parses the style"
    check "and the palette it read is the fixture's, not the machine's" \
      "$([[ $(grep -c 'rgba ( 17, 34, 51' "$TMP/dump") -ge 1 ]] && echo fixture || echo elsewhere)" "fixture"
  else
    fail "rofi refused the style: $(head -1 "$TMP/dumperr")"
  fi
else
  pass "rofi is not installed here, so the style is not parsed"
fi

# ---- the migration adds the stub to a machine that already exists ------------

mig_home="$TMP/mighome"; mkdir -p "$mig_home/.config/rofi"
HOME="$mig_home" "$BASH_BIN" "$MIGRATION" >"$TMP/migout" 2>&1
check "the migration writes the stub" \
  "$([[ -f $mig_home/.config/rofi/screenshot/style.rasi ]] && echo written || echo missing)" "written"
check "byte for byte the same as the shipped one" \
  "$(cmp -s "$STUB_STYLE" "$mig_home/.config/rofi/screenshot/style.rasi" && echo same || echo differs)" "same"

printf 'mine\n' >"$mig_home/.config/rofi/screenshot/style.rasi"
HOME="$mig_home" "$BASH_BIN" "$MIGRATION" >"$TMP/migout2" 2>&1
check "a stub already there is left exactly as it was" \
  "$(cat "$mig_home/.config/rofi/screenshot/style.rasi")" "mine"
check "and says why" "$(grep -c 'left alone' "$TMP/migout2")" "1"

mkdir -p "$TMP/norofi"
HOME="$TMP/norofi" "$BASH_BIN" "$MIGRATION" >"$TMP/migout3" 2>&1
check "a home with no rofi config is left alone" \
  "$([[ -e $TMP/norofi/.config/rofi ]] && echo created || echo none)" "none"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
