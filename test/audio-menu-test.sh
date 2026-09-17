#!/bin/bash
# Checks the sound menu behind SUPER + S, and the noise filter change that lets
# it keep suppression on the chosen microphone.
#
# Nothing here switches a real device, opens a menu or restarts audio. pactl,
# rofi, notify-send and systemctl are stubs, and the PATH each run gets holds
# only the stubs plus the real tools linked in by name. /usr/bin is never on it.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MENU="$REPO/.local/bin/hyprsimple-audio-menu.sh"
STYLE="$REPO/default/rofi/audio/style.rasi"
STUB_STYLE="$REPO/.config/rofi/audio/style.rasi"
BINDINGS="$REPO/default/hypr/bindings"
DENOISE="$REPO/.config/pipewire/pipewire.conf.d/99-input-denoising.conf"
DENOISE_MIGRATION="$REPO/migrations/1789010000.sh"
STUB_MIGRATION="$REPO/migrations/1789010001.sh"
FIXTURES="$REPO/test/fixtures/denoise"
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
HOME_DIR="$TMP/home"; mkdir -p "$HOME_DIR/.config/rofi/audio"
cp "$STUB_STYLE" "$HOME_DIR/.config/rofi/audio/style.rasi"

for tool in jq cat md5sum cut grep cmp cp; do ln -sf "$(command -v "$tool")" "$STUB/$tool"; done

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
# pactl answers from fixture files and records every change it is asked for.
cat >"$STUB/pactl" <<'STUBEOF'
#!/bin/bash
case "$1" in
-f)
  [[ ${LIST_FAILS:-} == yes ]] && exit 1
  case "$4" in
  sinks) cat "$SINKS_JSON" ;;
  sources) cat "$SOURCES_JSON" ;;
  esac
  ;;
get-default-sink) printf '%s\n' "$DEFAULT_SINK" ;;
get-default-source) printf '%s\n' "$DEFAULT_SOURCE" ;;
set-default-sink | set-default-source)
  printf '%s %s\n' "$1" "$2" >>"$PACTL_LOG"
  exit "${SET_RC:-0}"
  ;;
esac
STUBEOF
chmod +x "$STUB/rofi" "$STUB/notify-send" "$STUB/pactl"

# What this machine reports, trimmed to the fields that matter, plus the cases
# that must not be offered: a filter sink, the noise filter's own source, and a
# monitor source. The bluetooth microphone has a link-group, because
# WirePlumber builds it as a loopback, and must still be offered.
cat >"$TMP/sinks.json" <<'JSONEOF'
[
  {"name":"alsa_output.pci-0000_00_1f.3.analog-stereo","description":"Built-in Audio Analog Stereo","properties":{"device.api":"alsa","priority.session":"1009"}},
  {"name":"bluez_output.DC_50_85_59_6F_C0.1","description":"Monster Airstar M500","properties":{"device.api":"bluez5","priority.session":"1010"}},
  {"name":"effect_input.eq","description":"Equalizer Sink","properties":{"node.link-group":"filter-chain-1-2"}}
]
JSONEOF
cat >"$TMP/sources.json" <<'JSONEOF'
[
  {"name":"rnnoise_source","description":"Noise Canceling source","properties":{"node.link-group":"filter-chain-959-29"}},
  {"name":"alsa_output.pci-0000_00_1f.3.analog-stereo.monitor","description":"Monitor of Built-in Audio","properties":{"device.api":"alsa"}},
  {"name":"alsa_input.pci-0000_00_1f.3.analog-stereo","description":"Built-in Audio Analog Stereo","properties":{"device.api":"alsa","priority.session":"2009"}},
  {"name":"bluez_input.DC:50:85:59:6F:C0","description":"Monster Airstar M500","properties":{"device.api":"bluez5","node.link-group":"loopback-962-18","priority.session":"2010"}}
]
JSONEOF

INPUT="$TMP/menu-input"; ARGS="$TMP/rofi-args"
NLOG="$TMP/notifications"; PLOG="$TMP/pactl"

open_menu() {
  : >"$INPUT"; : >"$ARGS"; : >"$NLOG"; : >"$PLOG"
  ROFI_INPUT="$INPUT" ROFI_ARGS="$ARGS" ROFI_PICK="${1-}" NOTIFY_LOG="$NLOG" \
    PACTL_LOG="$PLOG" SINKS_JSON="${SINKS:-$TMP/sinks.json}" SOURCES_JSON="${SOURCES:-$TMP/sources.json}" \
    DEFAULT_SINK="${DSINK-bluez_output.DC_50_85_59_6F_C0.1}" \
    DEFAULT_SOURCE="${DSOURCE-bluez_input.DC:50:85:59:6F:C0}" \
    SET_RC="${SET_RC:-0}" LIST_FAILS="${LIST_FAILS:-}" HOME="$HOME_DIR" PATH="$STUB" \
    "$BASH_BIN" "$MENU" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

# ---- anti-vacuity -------------------------------------------------------------

check "the real pactl is unreachable from the restricted PATH" "$(PATH="$STUB" command -v pactl)" "$STUB/pactl"
check "and so is the real rofi" "$(PATH="$STUB" command -v rofi)" "$STUB/rofi"

# ---- SUPER + S, and SUPER + F10 gone -----------------------------------------

binds() { cat "$BINDINGS"/*.lua | sed 's/^[[:space:]]*--.*//' | tr '\n' ' '; }
check "SUPER + S opens the sound menu" \
  "$(binds | grep -oE 'hl\.bind\("SUPER \+ S",[^)]*hyprsimple-audio-menu\.sh' | wc -l | tr -d ' ')" "1"
check "and SUPER + F10 is no longer bound" "$(binds | grep -c 'SUPER + F10')" "0"
check "and nothing else is bound to SUPER + S" "$(binds | grep -o 'hl.bind("SUPER + S"' | wc -l | tr -d ' ')" "1"

# ---- what the menu offers -----------------------------------------------------

open_menu 0
check "the menu lists two speakers and two microphones" "$(wc -l <"$INPUT" | tr -d ' ')" "4"
check "speakers come first" "$(sed -n '1p;2p' "$INPUT" | grep -c 'Speaker')" "2"
check "then microphones" "$(sed -n '3p;4p' "$INPUT" | grep -c 'Mic')" "2"
check "the bluetooth microphone is offered, though WirePlumber builds it as a loopback" \
  "$(grep -c 'Mic .*Monster Airstar M500' "$INPUT")" "1"
check "the noise filter is not offered as a microphone" "$(grep -c 'Noise Canceling' "$INPUT")" "0"
check "nor is a monitor" "$(grep -c 'Monitor of' "$INPUT")" "0"
check "nor a filter sink" "$(grep -c 'Equalizer' "$INPUT")" "0"
check "the speaker in use is marked" "$(grep -c 'Speaker .*Monster Airstar M500  (in use)' "$INPUT")" "1"
check "and the microphone in use" "$(grep -c 'Mic .*Monster Airstar M500  (in use)' "$INPUT")" "1"
check "and nothing else is" "$(grep -c '(in use)' "$INPUT")" "2"

# A default source pinned to the filter marks no microphone, rather than
# pretending one of the real ones is in use.
DSOURCE=rnnoise_source open_menu ""
check "with the filter as the default, no microphone is marked in use" \
  "$(grep -c 'Mic .*(in use)' "$INPUT")" "0"

# ---- every line switches what it names ----------------------------------------

declare -a expected=(
  "set-default-sink alsa_output.pci-0000_00_1f.3.analog-stereo"
  "set-default-sink bluez_output.DC_50_85_59_6F_C0.1"
  "set-default-source alsa_input.pci-0000_00_1f.3.analog-stereo"
  "set-default-source bluez_input.DC:50:85:59:6F:C0"
)
wrong=()
for i in "${!expected[@]}"; do
  open_menu "$i"
  got=$(cat "$PLOG")
  [[ $got == "${expected[$i]}" ]] || wrong+=("$i wanted '${expected[$i]}' got '$got'")
done
wrong_str=""; ((${#wrong[@]} > 0)) && wrong_str="$(printf '%s; ' "${wrong[@]}")"
check "every line switches the device it names" "$wrong_str" ""

open_menu 2
check "a switch is announced with the kind and the device" \
  "$(grep -c 'Microphone: Built-in Audio Analog Stereo' "$NLOG")" "1"

SET_RC=1 open_menu 1
check "a switch pactl refuses is not announced as done" "$(grep -c 'Speaker:' "$NLOG")" "0"
check "but reported as failed" "$(grep -c 'Could not switch to Monster Airstar M500' "$NLOG")" "1"
check "and exits non-zero" "$([[ $(cat "$TMP/rc") != 0 ]] && echo failed || echo succeeded)" "failed"

# ---- answers that are not an index -------------------------------------------

open_menu "Speaker  Built-in"
check "a label instead of an index switches nothing" "$(wc -c <"$PLOG" | tr -d ' ')" "0"
check "and says so" "$(grep -c 'something unexpected' "$NLOG")" "1"

open_menu 4
check "an index past the end switches nothing" "$(wc -c <"$PLOG" | tr -d ' ')" "0"

open_menu ""
check "dismissing the menu switches nothing" "$(wc -c <"$PLOG" | tr -d ' ')" "0"
check "and says nothing" "$(wc -c <"$NLOG" | tr -d ' ')" "0"
check "and exits 0" "$(cat "$TMP/rc")" "0"

# ---- when the device list cannot be read --------------------------------------

LIST_FAILS=yes open_menu 0
check "when pactl cannot list devices the menu does not open" "$(wc -c <"$ARGS" | tr -d ' ')" "0"
check "and says why" "$(grep -c 'pipewire-pulse running' "$NLOG")" "1"

printf '[]\n' >"$TMP/empty.json"
SINKS="$TMP/empty.json" SOURCES="$TMP/empty.json" open_menu 0
check "with no devices at all the menu does not open" "$(wc -c <"$ARGS" | tr -d ' ')" "0"
check "and says so" "$(grep -c 'No audio devices found' "$NLOG")" "1"

# ---- rofi is asked for an index, in the audio style ----------------------------

open_menu ""
check "the menu is drawn with the audio style" "$(grep -c -- '-theme .*/.config/rofi/audio/style.rasi' "$ARGS")" "1"
check "and asks for an index" "$(grep -c -- '-format i' "$ARGS")" "1"

# ---- icons ---------------------------------------------------------------------

icons=$(python3 - "$MENU" <<'PYEOF'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
out = []
for kind in ("Speaker", "Mic"):
    m = re.search(r'labels\+=\("(.)\s+' + kind, src)
    out.append(f"{ord(m.group(1)):05X}" if m else "missing")
print(" ".join(out))
PYEOF
)
read -r speaker_cp mic_cp <<<"$icons"
is_pua() { [[ $1 =~ ^F[0-9A-F]{4}$ ]]; }
check "speaker lines start with a real icon" "$(is_pua "$speaker_cp" && echo glyph || echo "$speaker_cp")" "glyph"
check "and microphone lines too" "$(is_pua "$mic_cp" && echo glyph || echo "$mic_cp")" "glyph"
check "and the two are different" "$([[ $speaker_cp != "$mic_cp" ]] && echo different || echo same)" "different"

menu_family=$(grep -oE 'font: *"[^"]+"' "$STYLE" | head -1 | sed 's/.*"\(.*\)"/\1/; s/ [0-9]*$//')
installed=""
command -v fc-list >/dev/null 2>&1 && installed=$(fc-list -f '%{family[0]}\n' 2>/dev/null)
if [[ -n $menu_family ]] && grep -qiF "$menu_family" <<<"$installed"; then
  uncovered=()
  for cp in "$speaker_cp" "$mic_cp"; do
    families=$(fc-list -f '%{family[0]}\n' ":charset=$cp" 2>/dev/null)
    grep -qiF "$menu_family" <<<"$families" || uncovered+=("U+$cp")
  done
  check "and the menu's font covers both" "${uncovered[*]:-}" ""
else
  pass "the menu's font is not installed here, so icon coverage is not checked"
fi

# ---- the style follows the theme ---------------------------------------------

style_code() { python3 -c "
import re, sys
print(re.sub(r'/\*.*?\*/', '', open(sys.argv[1]).read(), flags=re.S))
" "$STYLE"; }
check "the style imports the theme's palette" "$(style_code | grep -c 'rofi-colors.rasi')" "1"
check "and hard codes no colour" "$(style_code | grep -cE '#[0-9A-Fa-f]{3,8}')" "0"
check "the user's stub imports the shipped style" \
  "$(grep -c '@import "hyprsimple/audio/style.rasi"' "$STUB_STYLE")" "1"

mig_home="$TMP/stubhome"; mkdir -p "$mig_home/.config/rofi"
HOME="$mig_home" "$BASH_BIN" "$STUB_MIGRATION" >"$TMP/stubmig" 2>&1
check "the stub migration writes the stub byte for byte" \
  "$(cmp -s "$STUB_STYLE" "$mig_home/.config/rofi/audio/style.rasi" && echo same || echo differs)" "same"
printf 'mine\n' >"$mig_home/.config/rofi/audio/style.rasi"
HOME="$mig_home" "$BASH_BIN" "$STUB_MIGRATION" >"$TMP/stubmig" 2>&1
check "and leaves one already there alone" "$(cat "$mig_home/.config/rofi/audio/style.rasi")" "mine"

# ---- the noise filter is smart, on the side WirePlumber reads ------------------
#
# WirePlumber reads filter.smart from the filter's main node, which for a
# microphone filter is the Audio/Source one. On the capture stream it would be
# ignored and suppression would silently stop following the chosen microphone.

props() { python3 - "$DENOISE" "$1" <<'PYEOF'
import re, sys
src = re.sub(r'#.*', '', open(sys.argv[1]).read())
m = re.search(sys.argv[2] + r'\s*=\s*\{(.*?)\}', src, re.S)
print(m.group(1) if m else "")
PYEOF
}
check "the source side is marked smart" "$(props playback.props | grep -c 'filter.smart = true')" "1"
check "and named" "$(props playback.props | grep -c 'filter.smart.name = ')" "1"
check "and is the Audio/Source node" "$(props playback.props | grep -c 'media.class = Audio/Source')" "1"
check "the capture stream is not" "$(props capture.props | grep -c 'filter.smart')" "0"
check "and no fixed target, so it follows the default microphone" "$(sed 's/#.*//' "$DENOISE" | grep -c 'filter.smart.target')" "0"

# ---- the denoise migration ---------------------------------------------------

# Fixtures are the versions hyprsimple shipped, saved as files because CI checks
# out shallow and git history is not there to read.
for v in v1 v2 v3; do
  sum=$(md5sum "$FIXTURES/$v.conf" | cut -d' ' -f1)
  check "shipped version $v is one the migration recognises" "$(grep -c "$sum" "$DENOISE_MIGRATION")" "1"
done

SYS="$TMP/sysbin"; mkdir -p "$SYS"
cp "$STUB"/* "$SYS/" 2>/dev/null
for tool in jq cat md5sum cut grep cmp cp mkdir; do ln -sf "$(command -v "$tool")" "$SYS/$tool"; done
cat >"$SYS/systemctl" <<'STUBEOF'
#!/bin/bash
[[ ${SESSION_UP:-} == yes ]]
STUBEOF
chmod +x "$SYS/systemctl"

run_denoise_migration() {
  : >"$PLOG"
  HOME="$1" HYPRSIMPLE_PATH="$REPO" SESSION_UP="${SESSION_UP:-}" PACTL_LOG="$PLOG" \
    SINKS_JSON="$TMP/sinks.json" SOURCES_JSON="$TMP/sources.json" \
    DEFAULT_SINK="bluez_output.DC_50_85_59_6F_C0.1" DEFAULT_SOURCE="${DSOURCE:-rnnoise_source}" \
    PATH="$SYS" "$BASH_BIN" "$DENOISE_MIGRATION" >"$TMP/denoise-out" 2>&1
}
denoise_home() {
  local h="$TMP/denoise-$1"
  mkdir -p "$h/.config/pipewire/pipewire.conf.d"
  printf '%s' "$h"
}
REL=".config/pipewire/pipewire.conf.d/99-input-denoising.conf"

for v in v1 v2 v3; do
  h=$(denoise_home "$v")
  cp "$FIXTURES/$v.conf" "$h/$REL"
  run_denoise_migration "$h"
  check "an unedited $v config is replaced with the smart one" \
    "$(cmp -s "$DENOISE" "$h/$REL" && echo replaced || echo kept)" "replaced"
done

h=$(denoise_home edited)
{ cat "$FIXTURES/v3.conf"; printf '# my own tweak\n'; } >"$h/$REL"
before=$(md5sum "$h/$REL" | cut -d' ' -f1)
run_denoise_migration "$h"
check "an edited config is left exactly as it was" "$(md5sum "$h/$REL" | cut -d' ' -f1)" "$before"
check "and the two lines to add are printed" "$(grep -c 'filter.smart' "$TMP/denoise-out")" "2"

h=$(denoise_home deleted)
run_denoise_migration "$h"
check "a deleted config, which is how suppression is turned off, is not recreated" \
  "$([[ -e $h/$REL ]] && echo recreated || echo absent)" "absent"

# The pin. Moved only with a session, only off the filter, and to the real
# microphone WirePlumber ranks highest.
h=$(denoise_home pin-tty); cp "$FIXTURES/v3.conf" "$h/$REL"
SESSION_UP="" run_denoise_migration "$h"
check "from a TTY the default microphone is not touched" "$(wc -c <"$PLOG" | tr -d ' ')" "0"

h=$(denoise_home pin-session); cp "$FIXTURES/v3.conf" "$h/$REL"
SESSION_UP=yes run_denoise_migration "$h"
check "with a session, a default pinned to the filter moves to the highest ranked microphone" \
  "$(cat "$PLOG")" "set-default-source bluez_input.DC:50:85:59:6F:C0"

h=$(denoise_home pin-real); cp "$FIXTURES/v3.conf" "$h/$REL"
SESSION_UP=yes DSOURCE="alsa_input.pci-0000_00_1f.3.analog-stereo" run_denoise_migration "$h"
check "a default already on a real microphone is left alone" "$(wc -c <"$PLOG" | tr -d ' ')" "0"
check "and the restart that applies the change is spelled out" "$(grep -c 'systemctl --user restart pipewire' "$TMP/denoise-out")" "1"

# ---- documented -------------------------------------------------------------

check "the README documents SUPER + S" "$(grep -c 'SUPER + S` | Open the sound menu' "$REPO/README.md")" "1"
check "and no longer documents SUPER + F10" "$(grep -c 'SUPER + F10' "$REPO/README.md")" "0"
check "and says what a bluetooth microphone costs" "$(grep -c 'call profile' "$REPO/README.md")" "1"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
