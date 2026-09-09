#!/bin/bash
# Audio moving to a bluetooth device when one connects.
#
# WirePlumber picks the default sink by priority and a bluetooth sink already
# outranks the built-in: 1010 against 1009, read off the machine this was
# reported from. What stops it taking over is an explicitly chosen default.
# find-selected-default-node.lua in WirePlumber 0.5 does
#
#   if current_configured_node == name then
#     priority = 30000 + priority
#
# so the chosen sink scores 31009 and no bluetooth device can outrank it.
# audio-switch.sh writes that key through `pactl set-default-sink`, so pressing
# SUPER + F10 once turned bluetooth auto-switching off for good.
#
# Nothing here touches the real audio. pactl and notify-send are stubs, the
# script is pointed at the stub through HYPRSIMPLE_PACTL rather than by PATH
# alone, and the PATH each run gets holds only the stubs plus the few real
# tools the script runs, linked in by name. /usr/bin is never on it: a probe
# that left it there is how a real command got run on the maintainer's own
# machine once.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WATCHER="$REPO/.local/bin/hyprsimple-audio-autoswitch.sh"
UNIT="$REPO/.config/systemd/user/hyprsimple-audio-autoswitch.service"
MIGRATION="$REPO/migrations/1788970000.sh"
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

# The real tools the watcher runs, read out of it rather than listed from
# memory. One missing from the list looks exactly like a bug in the watcher.
mapfile -t needed < <(
  sed 's/^[[:space:]]*#.*//' "$WATCHER" |
    grep -oE '\b(cut|grep|tr|awk|sed|tail|cat)\b' | sort -u
)
if ((${#needed[@]} < 4)); then
  fail "read ${#needed[@]} real tools out of the watcher, which is fewer than it runs"
else
  pass "linking ${#needed[@]} real tools into the restricted PATH"
fi

STUB="$TMP/bin"
mkdir -p "$STUB"
for tool in "${needed[@]}"; do ln -sf "$(command -v "$tool")" "$STUB/$tool"; done
# The stubs below are shell scripts of their own and run a few tools the
# watcher does not. Linked separately, so the list read out of the watcher
# stays a statement about the watcher.
for tool in cat sed tail cmp; do
  [[ -e $STUB/$tool ]] || ln -sf "$(command -v "$tool")" "$STUB/$tool"
done

# A pactl that answers from files and acts on nothing.
#
# `list short sinks` walks a scripted timeline one step per call. The watcher
# reads the sink list once at startup and once per sink event, and those calls
# are sequential, so a counter is deterministic where a clock or a shared file
# written by the event stream would race.
cat >"$STUB/pactl" <<'PACTLEOF'
#!/bin/bash
case "$1" in
subscribe)
  cat "$EVENTS_FILE"
  ;;
set-default-sink)
  printf '%s\n' "$2" >>"$SWITCH_LOG"
  exit "${SET_DEFAULT_RC:-0}"
  ;;
list)
  if [[ $2 == short && $3 == sinks ]]; then
    step=$(cat "$STEP_FILE")
    step=$((step + 1))
    printf '%s' "$step" >"$STEP_FILE"
    line=$(sed -n "${step}p" "$STEPS_FILE")
    [[ -z $line ]] && line=$(tail -1 "$STEPS_FILE")
    [[ $line == "-" ]] && exit 0
    i=0
    for s in $line; do
      i=$((i + 1))
      printf '%s\t%s\tmodule\ts16le\tRUNNING\n' "$i" "$s"
    done
  elif [[ $2 == sinks ]]; then
    cat "$DESC_FILE"
  fi
  ;;
esac
PACTLEOF
cat >"$STUB/notify-send" <<'NOTIFYEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
NOTIFYEOF
chmod +x "$STUB/pactl" "$STUB/notify-send"

BUILTIN="alsa_output.pci-0000_00_1f.3.analog-stereo"
HEADSET="bluez_output.DC_50_85_59_6F_C0.1"
OTHER_BT="bluez_output.AA_BB_CC_DD_EE_FF.1"

cat >"$TMP/desc" <<DESCEOF
Sink #59
	Name: $BUILTIN
	Description: Built-in Audio Analog Stereo
Sink #68
	Name: $HEADSET
	Description: Monster Airstar M500
Sink #70
	Name: $OTHER_BT
	Description: Someone Elses Speaker
DESCEOF

# steps: one line per `list short sinks` call, the first being startup.
# events: one line per line pactl subscribe emits.
run_watcher() {
  local steps="$1" events="$2"
  printf '%s\n' "$steps" >"$TMP/steps"
  printf '%s\n' "$events" >"$TMP/events"
  printf '0' >"$TMP/step"
  : >"$TMP/switches"
  : >"$TMP/notifications"
  STEPS_FILE="$TMP/steps" EVENTS_FILE="$TMP/events" STEP_FILE="$TMP/step" \
    DESC_FILE="$TMP/desc" SWITCH_LOG="$TMP/switches" NOTIFY_LOG="$TMP/notifications" \
    SET_DEFAULT_RC="${SET_DEFAULT_RC:-0}" \
    HYPRSIMPLE_PACTL="$STUB/pactl" PATH="$STUB" \
    "$BASH_BIN" "$WATCHER" >/dev/null 2>&1
}
switches() { cat "$TMP/switches"; }
notifications() { cat "$TMP/notifications"; }

SINK_EVENT="Event 'new' on sink #68"

# ---- anti-vacuity, before anything rests on the stubs ----------------------
#
# Every check below is about which sink the watcher chooses. A PATH that could
# reach the real pactl would be choosing sinks on this machine instead.
check "the real pactl is unreachable from the restricted PATH" \
  "$(PATH="$STUB" command -v pactl)" "$STUB/pactl"
check "and the watcher is pointed at the stub explicitly as well" \
  "$(grep -c 'HYPRSIMPLE_PACTL' "$WATCHER")" "1"

# ---- a headset connecting ---------------------------------------------------

run_watcher "$BUILTIN
$BUILTIN $HEADSET" "$SINK_EVENT"
check "a bluetooth sink appearing becomes the default" "$(switches)" "$HEADSET"
check "and it is announced by description, not by node name" \
  "$(notifications | grep -c 'Switched to: Monster Airstar M500')" "1"

# ---- what must not happen ---------------------------------------------------

run_watcher "$BUILTIN $HEADSET
$BUILTIN $HEADSET" "$SINK_EVENT"
check "a headset already connected at startup is left alone" "$(switches)" ""
check "and nothing is announced" "$(notifications)" ""

run_watcher "$BUILTIN
$BUILTIN $HEADSET
$BUILTIN $HEADSET" "$SINK_EVENT
$SINK_EVENT"
check "a sink already switched to is not switched to twice" "$(switches)" "$HEADSET"

run_watcher "$BUILTIN
$BUILTIN $HEADSET
$BUILTIN" "$SINK_EVENT
$SINK_EVENT"
check "and a headset going away switches nothing" "$(switches)" "$HEADSET"

# Reconnecting is an appearance again, which is the case a naive "seen once"
# check would get wrong.
run_watcher "$BUILTIN
$BUILTIN $HEADSET
$BUILTIN
$BUILTIN $HEADSET" "$SINK_EVENT
$SINK_EVENT
$SINK_EVENT"
check "a headset that reconnects takes over again" \
  "$(switches | tr '\n' ' ')" "$HEADSET $HEADSET "

run_watcher "$BUILTIN
$BUILTIN alsa_output.usb-some-dac" "$SINK_EVENT"
check "a new sink that is not bluetooth is ignored" "$(switches)" ""

run_watcher "$BUILTIN
$BUILTIN $HEADSET" "Event 'change' on source #60
Event 'new' on client #123"
check "events that are not about sinks are ignored" "$(switches)" ""

# ---- the switch is checked, not assumed -------------------------------------
#
# The sink list is a moment old. A headset that drops in between leaves the
# sound where it was, and audio-switch.sh once announced that as a move.
SET_DEFAULT_RC=1 run_watcher "$BUILTIN
$BUILTIN $HEADSET" "$SINK_EVENT"
SET_DEFAULT_RC=0
check "a failed switch is attempted" "$(switches)" "$HEADSET"
check "but never announced as a success" "$(notifications | grep -c 'Switched to')" "0"

# ---- two devices ------------------------------------------------------------

run_watcher "$BUILTIN
$BUILTIN $HEADSET
$BUILTIN $HEADSET $OTHER_BT" "$SINK_EVENT
$SINK_EVENT"
check "a second bluetooth device appearing takes over in turn" \
  "$(switches | tr '\n' ' ')" "$HEADSET $OTHER_BT "

# ---- the unit ---------------------------------------------------------------

check "the unit ships" "$([[ -f $UNIT ]] && echo present || echo missing)" "present"
check "it restarts, because pactl subscribe ends when pipewire-pulse does" \
  "$(grep -c '^Restart=always' "$UNIT")" "1"
check "and stops with the session, like the battery monitor" \
  "$(grep -c '^PartOf=graphical-session.target' "$UNIT")" "1"
check "and starts with it" "$(grep -c '^WantedBy=graphical-session.target' "$UNIT")" "1"
check "and runs the watcher" \
  "$(grep -c 'ExecStart=%h/.local/bin/hyprsimple-audio-autoswitch.sh' "$UNIT")" "1"
check "and says how to turn it off" "$(grep -c 'systemctl --user disable' "$UNIT")" "1"

check "install.sh enables it" \
  "$(sed 's/^[[:space:]]*#.*//' "$REPO/install.sh" | grep -c 'systemctl --user enable hyprsimple-audio-autoswitch.service')" "1"
# enable, not enable --now: the unit is wanted by graphical-session.target and
# the installer runs where that target is not up. The battery timer carries the
# same rule and the same comment.
check "and does not start it during the install" \
  "$(sed 's/^[[:space:]]*#.*//' "$REPO/install.sh" | grep -c 'enable --now hyprsimple-audio-autoswitch')" "0"

# ---- the migration, for installs that already exist -------------------------
#
# ~/.config is copied once and never overwritten, so a new unit reaches an
# existing machine only through a migration.

H="$TMP/home"
mkdir -p "$H"
run_migration() {
  HOME="$H" HYPRSIMPLE_PATH="$REPO" PATH="$STUB:$(dirname "$BASH_BIN")" \
    "$BASH_BIN" "$MIGRATION" >"$TMP/mig" 2>&1
}
# systemctl is stubbed for the migration only. Without it the migration would
# reach the maintainer's own session manager.
printf '#!/bin/bash\nexit 1\n' >"$STUB/systemctl"
chmod +x "$STUB/systemctl"

run_migration
check "the migration delivers the unit" \
  "$([[ -f $H/.config/systemd/user/hyprsimple-audio-autoswitch.service ]] && echo delivered || echo missing)" \
  "delivered"
check "and it is the shipped one" \
  "$(cmp -s "$UNIT" "$H/.config/systemd/user/hyprsimple-audio-autoswitch.service" && echo same || echo different)" "same"
check "and it says how to turn it off" "$(grep -c 'disable --now' "$TMP/mig")" "1"

# Run twice: a migration that rewrites on every run would overwrite an edit.
printf 'my own version\n' >"$H/.config/systemd/user/hyprsimple-audio-autoswitch.service"
run_migration
check "a unit already there is left exactly as it was" \
  "$(cat "$H/.config/systemd/user/hyprsimple-audio-autoswitch.service")" "my own version"
check "and it says so rather than silently skipping" \
  "$(grep -c 'left alone' "$TMP/mig")" "1"

# ---- documented -------------------------------------------------------------

for doc in README.md FAQ.md; do
  if grep -q 'hyprsimple-audio-autoswitch.service' "$REPO/$doc"; then
    pass "$doc says how to turn it off"
  else
    fail "$doc does not mention the service, so there is no way to find it"
  fi
done
check "and the FAQ explains why it was stuck, not just how to fix it" \
  "$(grep -c '30000 + priority' "$REPO/FAQ.md")" "1"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
