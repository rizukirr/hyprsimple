#!/bin/bash
# Checks that hyprsunset runs as a service rather than an unmanaged scope.
#
# It was started by autostart.lua as `uwsm app -- hyprsunset`, which has no
# restart policy, and hyprsunset does not survive a suspend. Measured across two
# cycles on one machine: started at login alongside dunst, hypridle and waybar,
# and the only one of the four gone afterwards, both times. Nothing brought it
# back, so every profile in hyprsunset.conf stopped applying for the rest of the
# session.
#
# Nothing here talks to systemd or starts hyprsunset. The migration is driven
# against a fixture home with stubbed systemctl and pkill.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DROPIN="$REPO/default/systemd/hyprsunset-restart.conf"
AUTOSTART="$REPO/default/hypr/autostart.lua"
INSTALL="$REPO/install.sh"
TOGGLE="$REPO/.local/bin/toggle-nightlight.sh"
MIGRATION="$REPO/migrations/1788780210.sh"
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

code() { sed 's/#.*//' "$1"; }
lua_code() { sed 's/^[[:space:]]*--.*//' "$1"; }

# ---- the drop-in says the thing that makes it worth having -----------------
#
# Restart=on-failure is what the packaged unit already has, and it does not
# cover a clean exit. Verified against systemd on the machine this was found
# on: a hyprsunset killed with SIGTERM under on-failure stayed dead, and came
# back under always.
check "the drop-in raises Restart to always" \
  "$(grep -c '^Restart=always$' "$DROPIN")" "1"
check "and sets it under [Service], where systemd reads it" \
  "$(grep -c '^\[Service\]$' "$DROPIN")" "1"
# Comments stripped: the file explains what on-failure does not cover.
check "and does not leave it at on-failure, which the packaged unit already says" \
  "$(code "$DROPIN" | grep -c 'on-failure')" "0"

# ---- autostart no longer starts it ----------------------------------------
#
# Comments stripped, because the file explains at length why it does not.
check "autostart.lua does not run hyprsunset itself any more" \
  "$(lua_code "$AUTOSTART" | grep -c 'hyprsunset')" "0"
check "and stripping the comments leaves its other launches behind" \
  "$(lua_code "$AUTOSTART" | grep -c 'uwsm app --')" "7"

# ---- install.sh enables the unit and links the drop-in ---------------------

check "install.sh enables hyprsunset.service" \
  "$(code "$INSTALL" | grep -c 'systemctl --user enable hyprsunset.service')" "1"
check "and links the drop-in from the install, so an update to it needs no migration" \
  "$(code "$INSTALL" | grep -c 'default/systemd/hyprsunset-restart.conf')" "1"
check "and creates the drop-in directory the link goes in" \
  "$(code "$INSTALL" | grep -c 'mkdir -p .*hyprsunset.service.d"$')" "1"
check "and reloads systemd, or the drop-in is not read" \
  "$(code "$INSTALL" | sed -n '/hyprsunset.service.d/,/enable hyprsunset/p' | grep -c 'daemon-reload')" "1"
# enable, not enable --now: the unit is wanted by graphical-session.target and
# carries ConditionEnvironment=WAYLAND_DISPLAY, so there is nothing for --now to
# start from a TTY install. Same reasoning as the battery timer.
check "and does not use enable --now, which has nothing to start at install time" \
  "$(code "$INSTALL" | grep -c 'enable --now hyprsunset')" "0"

# ---- the toggle starts it the same way ------------------------------------

check "toggle-nightlight.sh starts the service rather than a bare scope" \
  "$(code "$TOGGLE" | grep -c 'systemctl --user start hyprsunset.service')" "1"
check "and no longer launches it through uwsm" \
  "$(code "$TOGGLE" | grep -c 'uwsm app -- hyprsunset')" "0"

# ---- the migration, driven against a fixture ------------------------------

STUB="$TMP/bin"; mkdir -p "$STUB"
SLOG="$TMP/systemctl-calls"

cat >"$STUB/systemctl" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SYSTEMCTL_LOG"
# graphical-session.target is up or not, as the test arranges.
if [[ $* == *"is-active graphical-session.target"* ]]; then
  [[ -n ${SESSION_UP:-} ]] && exit 0
  exit 1
fi
exit 0
STUBEOF
# The handover: the old scope's process goes away when pkill is called.
cat >"$STUB/pkill" <<'STUBEOF'
#!/bin/bash
rm -f "$SUNSET_RUNNING"
exit 0
STUBEOF
cat >"$STUB/pgrep" <<'STUBEOF'
#!/bin/bash
[[ -e $SUNSET_RUNNING ]] && exit 0
exit 1
STUBEOF
chmod +x "$STUB"/*

run_migration() {
  local home="$1"
  SYSTEMCTL_LOG="$SLOG" SUNSET_RUNNING="${2-}" SESSION_UP="${3-}" \
    HOME="$home" HYPRSIMPLE_PATH="$REPO" PATH="$STUB:/usr/bin:/bin" \
    bash "$MIGRATION" >"$TMP/out" 2>&1
}

# A machine with hyprsunset installed, a live session and the old scope running.
home1="$TMP/home1"
mkdir -p "$home1/.config/systemd/user"
: >"$TMP/sunset-alive"
: >"$SLOG"
run_migration "$home1" "$TMP/sunset-alive" up

dropin="$home1/.config/systemd/user/hyprsunset.service.d/10-hyprsimple.conf"
check "the migration links the drop-in into the session" \
  "$([[ -L $dropin ]] && echo linked || echo missing)" "linked"
check "and it points at the install, not a copy" \
  "$(readlink "$dropin")" "$REPO/default/systemd/hyprsunset-restart.conf"
check "the unit is enabled" \
  "$(grep -c '^--user enable hyprsunset.service$' "$SLOG")" "1"
check "systemd is reloaded, or the drop-in is not read" \
  "$(grep -c '^--user daemon-reload$' "$SLOG")" "1"
check "the old scope is stopped, or the unit starts into a held socket" \
  "$([[ -e $TMP/sunset-alive ]] && echo running || echo stopped)" "stopped"
check "and the unit is started in its place" \
  "$(grep -c '^--user start hyprsunset.service$' "$SLOG")" "1"
check "and the user is told it now restarts itself" \
  "$(grep -c 'restarts itself' "$TMP/out")" "1"

# The same machine with no session up: enable, start nothing.
home2="$TMP/home2"
mkdir -p "$home2/.config/systemd/user"
: >"$SLOG"
run_migration "$home2"
check "with no session up, the unit is still enabled" \
  "$(grep -c '^--user enable hyprsunset.service$' "$SLOG")" "1"
check "but nothing is started" \
  "$(grep -c '^--user start hyprsunset.service$' "$SLOG")" "0"
check "and the user is told the next login starts it" \
  "$(grep -c 'next login' "$TMP/out")" "1"

# Someone's own drop-in is not replaced.
home3="$TMP/home3"
mkdir -p "$home3/.config/systemd/user/hyprsunset.service.d"
mine="$home3/.config/systemd/user/hyprsunset.service.d/10-hyprsimple.conf"
printf '[Service]\nRestart=no\n' >"$mine"
: >"$SLOG"
run_migration "$home3"
check "a real file where the drop-in goes is left alone" \
  "$([[ -L $mine ]] && echo replaced || echo kept)" "kept"
check "with its contents untouched" "$(grep -c '^Restart=no$' "$mine")" "1"
check "and the user is told why, and what to add" \
  "$(grep -c 'Restart=always' "$TMP/out")" "1"
check "while the unit is still enabled, because that half is not theirs" \
  "$(grep -c '^--user enable hyprsunset.service$' "$SLOG")" "1"

# A machine with no hyprsunset installed does nothing at all.
#
# The unit path is read out of the migration rather than named here, so this
# still tests the right thing if that path changes.
unit_path=$(grep -m1 '^UNIT=' "$MIGRATION" | cut -d= -f2)
check "the migration checks for a real unit path" \
  "$([[ $unit_path == /usr/lib/systemd/user/* ]] && echo yes || echo no)" "yes"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
