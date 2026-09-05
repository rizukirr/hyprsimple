#!/bin/bash
# Two of the six recording keybinds have never worked.
#
# SUPER+ALT+R and SUPER+SHIFT+ALT+R are "Record Region/Screen (System Audio)".
# Both go through AUDIO_MODE=internal, which found its device with:
#
#   pw-cli ls Node | grep monitor | head -n 1 | awk '{print $2}'
#
# A monitor is a port in pipewire, not a node, so `pw-cli ls Node` never prints
# the word. Measured on a working desktop with audio playing: zero matching
# lines. The script then took its own empty-string branch and exited 1 with
# "No monitor source found for internal audio!", on every machine.
#
# Behind that sat a second one. The device was passed as --audio="pw:NAME",
# which is wf-recorder's spelling. wl-screenrec, which is the recorder chosen on
# any machine without an NVIDIA GPU, declares --audio as a flag that takes no
# value and rejects the command if given one. Its device goes to --audio-device
# and wants a pactl source name. Confirmed against upstream's README:
#
#   wl-screenrec --audio --audio-device alsa_output...monitor
#
# And the recorder is backgrounded, so either failure produced no file, no
# indicator and no message.
#
# Nothing is recorded here. Both recorders, pactl, slurp and the NVIDIA
# predicate are stubs.

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
LOG="$TMP/calls"
NLOG="$TMP/notifications"

# The stubs have to outlive the script's liveness check and nothing more. An
# earlier version slept five seconds, which left four processes named
# wf-recorder on the machine after one run. screen-record.sh and
# waybar-screenrecording.sh both ask `pgrep -x wf-recorder` whether a recording
# is in progress, so those leftovers made two unrelated suites report a
# recording that was not happening. Each stub records its own pid and the trap
# kills exactly those, so nothing here can reach a real recorder.
PIDFILE="$TMP/stub-pids"
: >"$PIDFILE"
for rec in wf-recorder wl-screenrec; do
  cat >"$STUB/$rec" <<STUBEOF
#!/bin/bash
printf '$rec %s\\n' "\$*" >>"\$CALL_LOG"
printf '%s\\n' "\$\$" >>"\$STUB_PIDS"
exec sleep 2
STUBEOF
done

kill_stubs() {
  local pid
  while read -r pid; do
    [[ -n $pid ]] && kill "$pid" 2>/dev/null
  done <"$PIDFILE"
  : >"$PIDFILE"
}
trap 'kill_stubs; rm -rf "${TMP:?}"' EXIT

cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUBEOF

# pactl answers with whatever sink and source list the test arranges.
cat >"$STUB/pactl" <<'STUBEOF'
#!/bin/bash
case "$*" in
  "get-default-sink") printf '%s\n' "${DEFAULT_SINK:-}" ;;
  "list short sources") printf '%s' "${SOURCE_LIST:-}" ;;
esac
STUBEOF

# pw-cli is the old detection. It stays on PATH and prints a realistic node
# listing, so the check below shows the old approach finding nothing rather
# than the command simply being absent.
cat >"$STUB/pw-cli" <<'STUBEOF'
#!/bin/bash
cat <<'NODES'
	id 44, type PipeWire:Interface:Node/3
 		object.serial = "44"
 		node.name = "alsa_output.pci-0000_00_1f.3.analog-stereo"
	id 51, type PipeWire:Interface:Node/3
 		object.serial = "51"
 		node.name = "alsa_input.pci-0000_00_1f.3.analog-stereo"
NODES
STUBEOF

cat >"$STUB/slurp" <<'STUBEOF'
#!/bin/bash
echo "0,0 1920x1080"
STUBEOF
cat >"$STUB/pgrep" <<'STUBEOF'
#!/bin/bash
exit 1
STUBEOF
printf '#!/bin/bash\nexit 0\n' >"$STUB/pkill"
chmod +x "$STUB"/*

HOME_DIR="$TMP/home"
mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/Videos"

# The NVIDIA predicate decides the recorder, so the test sets its answer.
set_gpu() {
  if [[ $1 == nvidia ]]; then printf '#!/bin/bash\nexit 0\n' >"$HOME_DIR/.local/bin/hyprsimple-hw-nvidia.sh"
  else printf '#!/bin/bash\nexit 1\n' >"$HOME_DIR/.local/bin/hyprsimple-hw-nvidia.sh"; fi
  chmod +x "$HOME_DIR/.local/bin/hyprsimple-hw-nvidia.sh"
}

SINK="alsa_output.pci-0000_00_1f.3.analog-stereo"
SOURCES=$(printf '0\t%s.monitor\tPipeWire\ts16le\tSUSPENDED\n1\t%s\tPipeWire\ts16le\tSUSPENDED\n' "$SINK" "alsa_input.usb")

run_record() {
  : >"$LOG"; : >"$NLOG"
  set_gpu "$1"
  CALL_LOG="$LOG" NOTIFY_LOG="$NLOG" HOME="$HOME_DIR" STUB_PIDS="$PIDFILE" \
    DEFAULT_SINK="${4-$SINK}" SOURCE_LIST="${5-$SOURCES}" \
    HYPRSIMPLE_RECORDER_START_WAIT=0.05 \
    PATH="$STUB:/usr/bin:/bin" bash "$BIN/screen-record.sh" "$2" "$3" >/dev/null 2>&1
  kill_stubs
}

# --- the old detection really does find nothing -----------------------------
#
# Asserted rather than described, so the premise of this whole suite is checked.
old_result=$(PATH="$STUB:/usr/bin:/bin" bash -c "pw-cli ls Node | grep monitor | head -n 1 | awk '{print \$2}'")
check "pw-cli ls Node names no monitor, which is what broke both keybinds" \
  "$old_result" ""

# --- internal audio now resolves a device -----------------------------------

run_record nvidia region internal
check "internal audio no longer reports a missing monitor source" \
  "$(grep -c 'No monitor source found' "$NLOG")" "0"
check "and wf-recorder is given the device as the value of --audio" \
  "$(grep -c -- "--audio=$SINK.monitor" "$LOG")" "1"
check "and not the pw: prefix, which its pulse backend cannot resolve" \
  "$(grep -c -- '--audio=pw:' "$LOG")" "0"

run_record intel region internal
check "wl-screenrec gets --audio as a bare flag" \
  "$(grep -cE -- 'wl-screenrec --audio --audio-device' "$LOG")" "1"
check "and never as --audio=<device>, which it rejects outright" \
  "$(grep -c -- 'wl-screenrec --audio=' "$LOG")" "0"
check "and the device is the pactl source name" \
  "$(grep -c -- "--audio-device $SINK.monitor" "$LOG")" "1"

# --- a sink with no monitor is still reported -------------------------------

run_record nvidia region internal "$SINK" ""
check "a sink whose monitor is not in the source list is reported" \
  "$(grep -c 'No monitor source found' "$NLOG")" "1"
check "and no recorder is started" "$(wc -l <"$LOG" | tr -d ' ')" "0"

run_record nvidia region internal "" "$SOURCES"
check "no default sink is reported too" \
  "$(grep -c 'No monitor source found' "$NLOG")" "1"

# --- the other two audio modes are unchanged --------------------------------

run_record nvidia region mic
check "mic passes a bare --audio to wf-recorder" \
  "$(grep -c -- 'wf-recorder --audio -f' "$LOG")" "1"
run_record intel region mic
check "and to wl-screenrec" "$(grep -c -- 'wl-screenrec --audio -f' "$LOG")" "1"

run_record nvidia region none
check "none passes no audio flag at all" "$(grep -c -- '--audio' "$LOG")" "0"
check "but still records" "$(grep -c '^wf-recorder ' "$LOG")" "1"

# --- the recorder is chosen by GPU, and the geometry reaches it -------------

run_record nvidia output none
check "an NVIDIA machine uses wf-recorder" "$(grep -c '^wf-recorder ' "$LOG")" "1"
run_record intel output none
check "any other machine uses wl-screenrec" "$(grep -c '^wl-screenrec ' "$LOG")" "1"
check "and the selected geometry is passed through" \
  "$(grep -c -- '-g 0,0 1920x1080' "$LOG")" "1"

# --- a recorder that dies immediately is reported ---------------------------

printf '#!/bin/bash\nprintf "wf-recorder %%s\\n" "$*" >>"$CALL_LOG"\nexit 2\n' >"$STUB/wf-recorder"
chmod +x "$STUB/wf-recorder"
run_record nvidia region none
check "a recorder that exits at once is reported rather than ignored" \
  "$(grep -c 'failed to start' "$NLOG")" "1"

# This suite once left four processes named wf-recorder running, which made
# waybar-refresh-test and notification-idiom-test see a recording in progress.
# Assert the cleanup rather than trust it.
leaked=0
while read -r pid; do
  [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null && leaked=$((leaked + 1))
done <"$PIDFILE"
check "no stub recorder is left running" "$leaked" "0"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
