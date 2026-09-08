#!/bin/bash
# Checks the recording menu behind SUPER + R.
#
# There were six keybinds, one per pairing of scope and audio source, five of
# them chords. This is one key and a list. The suite drives the menu with a
# stubbed rofi and a stubbed recorder, so no menu opens and nothing records.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
MENU="$BIN/hyprsimple-record-menu.sh"
STYLE="$REPO/default/rofi/record/style.rasi"
STUB_STYLE="$REPO/.config/rofi/record/style.rasi"
BINDS="$REPO/default/hypr/bindings/recording.lua"
MIGRATION="$REPO/migrations/1788880000.sh"
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

STUB="$TMP/bin"; mkdir -p "$STUB"
HOME_DIR="$TMP/home"; mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.config/rofi/record"

# rofi records what it was fed and answers with whatever the test chose. It
# never runs the real one: that would open a menu on the screen of whoever is
# running the suite, which has happened here before.
cat >"$STUB/rofi" <<'STUBEOF'
#!/bin/bash
cat >"$ROFI_INPUT"
printf '%s' "$*" >"$ROFI_ARGS"
printf '%s' "${ROFI_PICK:-}"
STUBEOF
cat >"$HOME_DIR/.local/bin/screen-record.sh" <<'STUBEOF'
#!/bin/bash
printf 'screen-record.sh %s\n' "$*" >>"$REC_LOG"
STUBEOF
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUBEOF
chmod +x "$STUB"/* "$HOME_DIR/.local/bin/screen-record.sh"
cp "$MENU" "$HOME_DIR/.local/bin/"
cp "$STUB_STYLE" "$HOME_DIR/.config/rofi/record/style.rasi"

INPUT="$TMP/menu-input"; ARGS="$TMP/rofi-args"
LOG="$TMP/recorder"; NLOG="$TMP/notifications"

recording() {
  if [[ $1 == yes ]]; then printf '#!/bin/bash\nexit 0\n' >"$STUB/pgrep"
  else printf '#!/bin/bash\nexit 1\n' >"$STUB/pgrep"; fi
  chmod +x "$STUB/pgrep"
}

open_menu() {
  : >"$LOG"; : >"$NLOG"
  ROFI_INPUT="$INPUT" ROFI_ARGS="$ARGS" ROFI_PICK="${1-}" \
    REC_LOG="$LOG" NOTIFY_LOG="$NLOG" HOME="$HOME_DIR" \
    PATH="$STUB:/usr/bin:/bin" bash "$HOME_DIR/.local/bin/hyprsimple-record-menu.sh" \
    >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

# ---- one key, not six -------------------------------------------------------

lua_code() { sed 's/^[[:space:]]*--.*//' "$BINDS"; }
check "there is one recording keybind" "$(lua_code | grep -c 'hl.bind')" "1"
check "and it is SUPER + R" "$(lua_code | grep -c 'hl.bind("SUPER + R"')" "1"
check "and it opens the menu rather than the recorder" \
  "$(lua_code | grep -c 'hyprsimple-record-menu.sh')" "1"
check "so no bind passes a scope and audio mode itself any more" \
  "$(lua_code | grep -cE 'screen-record\.sh (region|output)')" "0"

# ---- the six combinations, chosen by index ----------------------------------
#
# Each entry is picked in turn and the recorder's arguments read back. The
# mapping is the whole point of the menu, so every row is exercised rather than
# one of them standing for the rest.

recording no
declare -a expected=(
  "region mic" "region internal" "region none"
  "output mic" "output internal" "output none"
)

open_menu 0
check "the idle menu offers six ways to record" "$(wc -l <"$INPUT")" "6"

wrong=()
for i in "${!expected[@]}"; do
  open_menu "$i"
  got=$(sed 's/^screen-record.sh //' "$LOG")
  [[ $got == "${expected[$i]}" ]] || wrong+=("$i wanted '${expected[$i]}' got '$got'")
done
wrong_str=""; (( ${#wrong[@]} > 0 )) && wrong_str="$(printf '%s; ' "${wrong[@]}")"
check "every entry starts the recorder it names" "$wrong_str" ""

# The labels have to say which is which, or the list is six unlabelled rows.
open_menu 0
check "the menu names region and whole screen" \
  "$(grep -cE 'Region|Whole screen' "$INPUT")" "6"
check "and names all three audio sources" \
  "$(grep -cE 'microphone|system audio|no audio' "$INPUT")" "6"

# Every entry begins with an icon, and the icon is a real character.
#
# Three of them shipped with nothing there. The label read "  Region,
# microphone" with two leading spaces where the glyph should be, because the
# character was lost on the way into the file rather than because the font
# lacked it. Nothing noticed: the menu worked, the dispatch was by index, and
# the only sign was a gap in the list.
#
# The first character of each label is read out of the script and checked to be
# in the private use area the Nerd Font icons live in, which a space or a
# letter is not.
glyph_report=$(python3 - "$MENU" <<'PYEOF'
import re, sys

labels = []
for line in open(sys.argv[1]):
    m = re.search(r'"([^"]*(?:Region|Whole screen|Stop)[^"]*)"', line)
    if m:
        labels.append(m.group(1))

if len(labels) < 7:
    print(f"only {len(labels)} labels found")
    raise SystemExit(0)

bad = [l for l in labels if not l or not (0xE000 <= ord(l[0]) <= 0xF8FF or 0xF0000 <= ord(l[0]) <= 0xFFFFD)]
print("blank: " + ", ".join(repr(l) for l in bad) if bad else "all glyphed")
PYEOF
)
check "every menu entry starts with an icon" "$glyph_report" "all glyphed"

# The two kinds are told apart by their icon, not only by their words.
region_cp=$(python3 -c "
import re,sys
for line in open(sys.argv[1]):
    m = re.search(r'\"([^\"]*Region[^\"]*)\"', line)
    if m: print(f'{ord(m.group(1)[0]):05X}'); break
" "$MENU")
screen_cp=$(python3 -c "
import re,sys
for line in open(sys.argv[1]):
    m = re.search(r'\"([^\"]*Whole screen[^\"]*)\"', line)
    if m: print(f'{ord(m.group(1)[0]):05X}'); break
" "$MENU")
check "region and whole screen do not share an icon" \
  "$([[ $region_cp != "$screen_cp" ]] && echo different || echo same)" "different"

# And the font the menu asks rofi for actually has them, or they render as the
# missing-glyph box. Skipped where fontconfig cannot answer, which is CI.
menu_font=$(grep -oE 'font: *"[^"]+"' "$STYLE" | head -1 | sed 's/.*"\(.*\)"/\1/')
menu_family="${menu_font%% [0-9]*}"

# Skipped where the font itself is absent, not only where fontconfig is.
#
# A CI runner has fc-list and no Nerd Font, so every icon read as uncovered and
# this failed for a reason that has nothing to do with the menu. The question
# is whether the font the menu asks for covers the icons, and on a machine
# without that font there is nothing to answer.
installed_families=""
if command -v fc-list >/dev/null 2>&1; then
  installed_families=$(fc-list -f '%{family[0]}\n' 2>/dev/null)
fi

if [[ -n $menu_family ]] && grep -qiF "$menu_family" <<<"$installed_families"; then
  # The family list is captured before it is searched, not piped into grep -q.
  #
  # grep -q exits on its first match, which closes the pipe, and fc-list then
  # dies of SIGPIPE. This suite sets pipefail, so the pipeline reported failure
  # for a grep that had succeeded and every icon read as uncovered.
  uncovered=()
  for cp in "$region_cp" "$screen_cp"; do
    families=$(fc-list -f '%{family[0]}\n' ":charset=$cp" 2>/dev/null)
    grep -qiF "${menu_font%% [0-9]*}" <<<"$families" || uncovered+=("U+$cp")
  done
  uncovered_str=""; (( ${#uncovered[@]} > 0 )) && uncovered_str="$(printf '%s ' "${uncovered[@]}")"
  check "and the menu's font covers both icons" "$uncovered_str" ""
else
  pass "the menu's font is not installed here, so icon coverage is not checked"
fi

# ---- while recording, it offers to stop -------------------------------------

recording yes
open_menu 0
check "with a recording running the menu offers one thing" "$(wc -l <"$INPUT")" "1"
check "and that thing is stopping" "$(grep -c 'Stop recording' "$INPUT")" "1"
check "which stops the recorder" "$(grep -c 'screen-record.sh stop' "$LOG")" "1"
check "and it does not offer to start another" \
  "$(grep -cE 'Region|Whole screen' "$INPUT")" "0"

# ---- an answer that is not an index is refused ------------------------------
#
# rofi is asked for an index, so a label back means it answered in a shape this
# script did not ask for. Dispatching on it would run whichever entry the
# number happened to land on.

recording no
open_menu "  Region, microphone"
check "a label instead of an index starts nothing" "$(wc -c <"$LOG")" "0"
check "and says so" "$(grep -c 'something unexpected' "$NLOG")" "1"
check "and exits non-zero" \
  "$([[ $(cat "$TMP/rc") != "0" ]] && echo nonzero || echo zero)" "nonzero"

open_menu 99
check "an index past the end of the list starts nothing" "$(wc -c <"$LOG")" "0"
check "and says so too" "$(grep -c 'something unexpected' "$NLOG")" "1"

# Dismissing is not a failure and must be silent.
open_menu ""
check "dismissing the menu starts nothing" "$(wc -c <"$LOG")" "0"
check "and says nothing" "$(wc -c <"$NLOG")" "0"
check "and exits 0" "$(cat "$TMP/rc")" "0"

# ---- it asks rofi for the themed style --------------------------------------

recording no
open_menu 0
check "the menu is drawn with the record style, not rofi's default" \
  "$(grep -c -- '-theme .*/.config/rofi/record/style.rasi' "$ARGS")" "1"
check "and asks for an index rather than the line it displayed" \
  "$(grep -c -- '-format i' "$ARGS")" "1"

# ---- the style follows the theme -------------------------------------------
#
# Every colour comes from rofi-colors.rasi, which the theme switcher repoints
# on each theme change. A colour written into this file would keep one theme's
# palette while the rest of the desktop moved.

# Comments stripped first. The block at the top of the file explains why the
# palette is imported, and counting that explanation as a second import made
# this read 2 where it wanted 1.
style_code() { python3 -c "
import re, sys
print(re.sub(r'/\*.*?\*/', '', open(sys.argv[1]).read(), flags=re.S))
" "$STYLE"; }

check "the style imports the theme's palette" \
  "$(style_code | grep -c 'rofi-colors.rasi')" "1"
check "and hard codes no colour of its own" \
  "$(style_code | grep -cE '#[0-9A-Fa-f]{3,8}')" "0"
check "while still setting the colours it needs, from that palette" \
  "$([[ $(style_code | grep -cE '@(background|foreground|selected|background-alt)') -ge 8 ]] && echo enough || echo few)" "enough"

# The stub the script actually loads imports the shipped style.
check "the user's stub imports the shipped style" \
  "$(grep -c '@import "hyprsimple/record/style.rasi"' "$STUB_STYLE")" "1"

# rofi parses it. -dump-theme reads a theme and prints it without opening a
# window, so this cannot reach anyone's screen.
#
# HOME and XDG_CONFIG_HOME both point at a fixture, and the palette in it is
# this suite's own. The style imports ~/.config/rofi/rofi-colors.rasi, and
# without the redirection that resolved against the maintainer's real palette,
# so the check would have read whatever theme they happened to be on rather
# than proving the style resolves against the palette it is given.
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
    check "and the window colour resolves from the palette rather than a literal" \
      "$(grep -c 'background-color: *var(background)' "$TMP/dump")" "1"
    # The fixture palette is the one that was read, not the real one. If the
    # import had resolved elsewhere these values would not be here.
    # rofi normalises hex to rgba in its dump, so the fixture's values are
    # looked for in that form. 17, 34, 51 is #112233 and cannot have come from
    # any shipped theme's palette.
    # The value appears once in the * block and again wherever it is used, so
    # this asks that it is there at all rather than pinning how many times.
    check "and the palette it read is the fixture's, not the machine's" \
      "$([[ $(grep -c 'rgba ( 17, 34, 51' "$TMP/dump") -ge 1 ]] && echo fixture || echo elsewhere)" \
      "fixture"
  else
    fail "rofi refused the style: $(head -1 "$TMP/dumperr")"
  fi
else
  pass "rofi is not installed here, so the style is not parsed"
fi

# ---- the migration adds the stub to a machine that already exists -----------

mig_home="$TMP/mighome"; mkdir -p "$mig_home/.config/rofi"
HOME="$mig_home" bash "$MIGRATION" >"$TMP/migout" 2>&1
check "the migration writes the stub" \
  "$([[ -f $mig_home/.config/rofi/record/style.rasi ]] && echo written || echo missing)" "written"
check "byte for byte the same as the shipped one" \
  "$(cmp -s "$STUB_STYLE" "$mig_home/.config/rofi/record/style.rasi" && echo same || echo differs)" "same"

before=$(cat "$mig_home/.config/rofi/record/style.rasi")
HOME="$mig_home" bash "$MIGRATION" >"$TMP/migout2" 2>&1
check "running it again leaves the file alone" \
  "$([[ $(cat "$mig_home/.config/rofi/record/style.rasi") == "$before" ]] && echo unchanged || echo edited)" "unchanged"
check "and says why" "$(grep -c 'left alone' "$TMP/migout2")" "1"

mkdir -p "$TMP/norofi"
HOME="$TMP/norofi" bash "$MIGRATION" >"$TMP/migout3" 2>&1
check "a home with no rofi config is left alone" \
  "$([[ -e $TMP/norofi/.config/rofi ]] && echo created || echo none)" "none"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
