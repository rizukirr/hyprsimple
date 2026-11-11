#!/bin/bash
# Runs the real restart script against a real offscreen Quickshell.
#
# test/bar-test.sh stubs pgrep and qs, so it can only see what its stubs were
# written to do. Two faults passed it: a bar recovered from a crash has a bare
# command line, and qs list hides a bar launched on another display.
#
# The runtime directory is this suite's own, so these instances and a machine's
# real bar cannot see each other. uwsm is a stub, so a restart starts nothing.
#
# On a machine with systemd-coredump the deliberate crash adds one entry to
# coredumpctl per run. ulimit -c 0 does not stop that.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESTART="$REPO/.local/bin/hyprsimple-restart-bar.sh"
FIXTURE="$REPO/test/fixtures/restart-bar-by-command-line.bash"

command -v qs >/dev/null || { echo 'SKIP: Quickshell is required for this suite'; exit 77; }

# Under /tmp whatever TMPDIR says. Quickshell's socket lives under this path, and
# one too long for a unix socket leaves it with no IPC, so qs kill finds nothing.
TMP="$(mktemp -d /tmp/qs-bar.XXXXXX)"
STARTED=()
stop_started() {
  local pid
  for pid in "${STARTED[@]}"; do
    kill "$pid" 2>/dev/null
  done
}
trap 'rm -rf "${TMP:?}"; stop_started' EXIT

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

mkdir -p "$TMP/run" "$TMP/home" "$TMP/stub" "$TMP/install/default/quickshell"
chmod 700 "$TMP/run"
printf 'import Quickshell\nShellRoot {}\n' >"$TMP/install/default/quickshell/shell.qml"
BAR="$TMP/install/default/quickshell"
: >"$TMP/uwsm.log"

cat >"$TMP/stub/uwsm" <<STUBEOF
#!/bin/bash
printf 'uwsm %s\n' "\$*" >>"$TMP/uwsm.log"
STUBEOF
chmod +x "$TMP/stub/uwsm"

export HOME="$TMP/home" HYPRSIMPLE_PATH="$TMP/install" PATH="$TMP/stub:$PATH"
export XDG_RUNTIME_DIR="$TMP/run" XDG_CACHE_HOME="$TMP/home/.cache" XDG_CONFIG_HOME="$TMP/home/.config"
export XDG_DATA_HOME="$TMP/home/.local/share" XDG_STATE_HOME="$TMP/home/.local/state"
export QT_QPA_PLATFORM=offscreen WAYLAND_DISPLAY=fake-display DBUS_SESSION_BUS_ADDRESS="unix:path=$TMP/no-bus"
unset DISPLAY HYPRLAND_INSTANCE_SIGNATURE

bar_pids() {
  qs list -p "$BAR" --json --any-display 2>/dev/null | grep -oE '"pid": *[0-9]+' | grep -oE '[0-9]+'
}
bar_state() { [[ -n $(bar_pids) ]] && echo up || echo gone; }
starts() { wc -l <"$TMP/uwsm.log" | tr -d ' '; }

# Not wrapped in timeout: its own command line would hold "qs -p <path>", and a
# match on the command line would then find a bar that has lost it.
start_bar() {
  : >"$TMP/uwsm.log"
  setsid qs -p "$BAR" >>"$TMP/qs.log" 2>&1 &
  for _ in {1..50}; do
    BAR_PID=$(bar_pids | head -1)
    if [[ -n $BAR_PID ]]; then
      STARTED+=("$BAR_PID")
      return 0
    fi
    sleep 0.1
  done
  fail "the bar did not start"
  cat "$TMP/qs.log" >&2
  exit 1
}

# The script backgrounds the launch and gives a bar two seconds to quit.
run_script() {
  : >"$TMP/uwsm.log"
  "$@" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
  sleep 2
}

# ---- a healthy bar ----------------------------------------------------------

start_bar
run_script bash "$RESTART" --if-running
check "--if-running exits 0 on a healthy bar" "$(cat "$TMP/rc")" "0"
check "and stops it" "$(bar_state)" "gone"
check "and asks for a new one" "$(starts)" "1"

# ---- no display variables, as from SSH or a TTY ------------------------------

start_bar
run_script env -u WAYLAND_DISPLAY bash "$RESTART" --if-running
check "with no display variables, a healthy bar is stopped" "$(bar_state)" "gone"
check "and a new one asked for" "$(starts)" "1"

# ---- a bar Quickshell recovered from a crash ---------------------------------

# Quickshell will not restart an instance that crashes in its first ten seconds.
start_bar
sleep 12
kill -SEGV "$BAR_PID"
recovered=no
for _ in {1..40}; do
  if [[ $(tr '\0' ' ' </proc/"$BAR_PID"/cmdline 2>/dev/null) != *"qs -p"* && -n $(bar_pids) ]]; then
    recovered=yes
    break
  fi
  sleep 0.25
done
check "a crashed bar is recovered under the same pid" "$recovered" "yes"
# On a crash Quickshell forks a copy to hold the coredump. It keeps the old
# command line for a moment after the restarted bar has lost it, and a check
# made in that moment sees the copy and not the bar. pgrep never matches the
# copy once it has exited, so wait for it to go.
for _ in {1..50}; do
  pgrep -f -- "qs -p $BAR" >/dev/null || break
  sleep 0.1
done
pgrep -f -- "qs -p $BAR" >/dev/null
check "with a command line that no longer names its config" "$?" "1"
while read -r child; do
  STARTED+=("$child")
done < <(ps -o pid= --ppid "$BAR_PID")

# The mistake this suite exists for. It has to look wrong here, or nothing below
# proves anything.
run_script bash "$FIXTURE" --if-running
check "a script matching the command line leaves a recovered bar up" "$(bar_state)" "up"
check "and asks for no new one" "$(starts)" "0"

run_script bash "$RESTART" --toggle
check "--toggle leaves a recovered bar up" "$(bar_state)" "up"
check "and starts no second one" "$(starts)" "0"

run_script bash "$RESTART" --if-running
check "--if-running stops a recovered bar" "$(bar_state)" "gone"
check "and asks for a new one" "$(starts)" "1"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
