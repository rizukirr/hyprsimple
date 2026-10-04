#!/bin/bash
# Checks that the bar shows the notifications, that dunst is gone from what
# hyprsimple ships, and that the migration moves a machine that already has it
# without touching what is the user's.
#
# Nothing here sends a notification, stops a process or removes a package.
# pgrep, pkill, pacman, sudo and qs are stand-ins that record what they were
# asked, and every home is a directory of this suite's own.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BAR="$REPO/default/quickshell"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

BASH_BIN="$(command -v bash)"

# ---- the bar is the notification daemon -----------------------------------------

check "the bar runs a notification server" \
  "$(grep -c '^    NotificationServer {' "$BAR/notifications/Notifications.qml")" "1"
check "and shows what arrives" "$(grep -c '^    NotificationPopups {}' "$BAR/shell.qml")" "1"
check "its bell opens the history" \
  "$(grep -c 'onClicked: bar.toggle("notifications")' "$BAR/bar/Bar.qml")" "1"
check "which is a panel of that name" \
  "$(grep -c 'readonly property string name: "notifications"' "$BAR/notifications/NotificationSidebar.qml")" "1"
for call in dismissNotifications toggleVisible; do
  check "the bar answers $call over ipc" "$(grep -c "function $call(): void" "$BAR/shell.qml")" "1"
done

# ---- nothing shipped starts or installs dunst -----------------------------------

check "dunst is in neither package list" \
  "$(cat "$REPO/packages.txt" "$REPO/aur-packages.txt" | grep -cx 'dunst')" "0"
check "no dunst config is shipped" \
  "$([[ -e $REPO/.config/dunst || -e $REPO/default/dunst ]] && echo shipped || echo none)" "none"
check "nor a dunst colour template" \
  "$(find "$REPO/.config/hypr/themes/templates" -name '*dunst*' | wc -l | tr -d ' ')" "0"

# Comments stripped, since several files say what happened before.
callers=()
while IFS= read -r f; do
  sed 's/^[[:space:]]*#.*//; s/^[[:space:]]*--.*//; s/^[[:space:]]*\/\/.*//' "$f" |
    grep -qE '(^|[^a-zA-Z_-])(dunst|dunstctl|dunstify)([^a-zA-Z_-]|$)' && callers+=("${f#"$REPO"/}")
done < <(find "$REPO/.local/bin" "$REPO/default" "$REPO/.config/hypr" "$REPO/install.sh" \
  -type f \( -name '*.sh' -o -name '*.lua' -o -name '*.conf' -o -name '*.qml' \))
check "no shipped script or config names dunst in its code" "${callers[*]:-}" ""

# ---- the scripts that talked to dunst talk to the bar ---------------------------

STUB="$TMP/stub"; mkdir -p "$STUB"
for tool in grep rm cat; do ln -sf "$(command -v "$tool")" "$STUB/$tool"; done
cat >"$STUB/qs" <<'STUBEOF'
#!/bin/bash
printf 'qs %s\n' "$*" >>"$CALLS"
STUBEOF
# pgrep answers from $DUNST_RUNNING, pacman -Qi from $DUNST_INSTALLED, and sudo
# records the removal it was asked for and answers from $REMOVAL_WORKS.
cat >"$STUB/pgrep" <<'STUBEOF'
#!/bin/bash
[[ ${DUNST_RUNNING:-} == yes ]]
STUBEOF
cat >"$STUB/pkill" <<'STUBEOF'
#!/bin/bash
printf 'pkill %s\n' "$*" >>"$CALLS"
STUBEOF
cat >"$STUB/pacman" <<'STUBEOF'
#!/bin/bash
[[ $1 == -Qi && ${DUNST_INSTALLED:-} == yes ]]
STUBEOF
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALLS"
[[ ${REMOVAL_WORKS:-yes} == yes ]]
STUBEOF
chmod +x "$STUB"/qs "$STUB"/pgrep "$STUB"/pkill "$STUB"/pacman "$STUB"/sudo
for tool in qs pkill pacman sudo; do
  check "the real $tool is unreachable from here" "$(PATH="$STUB" command -v "$tool")" "$STUB/$tool"
done

: >"$TMP/calls"
CALLS="$TMP/calls" HOME="$TMP/dismiss-home" HYPRSIMPLE_PATH="$TMP/install" PATH="$STUB" \
  "$BASH_BIN" "$REPO/.local/bin/notification-dismiss.sh" >/dev/null 2>&1
check "SUPER + D asks the bar to dismiss the notifications" \
  "$(cat "$TMP/calls")" "qs -p $TMP/install/default/quickshell ipc call bar dismissNotifications"

# ---- the migration --------------------------------------------------------------

MIGRATION="$(grep -l 'Move notifications from dunst to the bar' "$REPO"/migrations/*.sh | head -1)"
check "the migration was found" "$([[ -n $MIGRATION ]] && echo found || echo missing)" "found"

# An install as it stands before this update.
old_home() {
  local h="$TMP/home-$1"
  mkdir -p "$h/.config/dunst/dunstrc.d" "$h/.config/hypr/bindings" "$h/.local/bin"
  printf '# mine\n' >"$h/.config/dunst/dunstrc"
  printf '# my own drop-in\n' >"$h/.config/dunst/dunstrc.d/99-mine.conf"
  ln -s "$TMP/install/default/dunst/10-hyprsimple.conf" "$h/.config/dunst/dunstrc.d/10-hyprsimple.conf"
  printf '[global]\n' >"$h/.config/dunst/dunstrc.d/90-theme.conf"
  printf '#!/bin/bash\n' >"$h/.local/bin/hyprsimple-restart-dunst.sh"
  printf 'hl.bind("SUPER + T", hl.dsp.exec_cmd(vars.terminal), { description = "Terminal" })\n' \
    >"$h/.config/hypr/bindings/applications.lua"
  printf '%s' "$h"
}
migrate() {
  : >"$TMP/calls"
  HOME="$1" CALLS="$TMP/calls" PATH="${MPATH:-$STUB}" "$BASH_BIN" "$MIGRATION" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}
exists() { [[ -e $1 || -L $1 ]] && echo present || echo gone; }

h=$(old_home plain)
DUNST_RUNNING=yes DUNST_INSTALLED=yes migrate "$h"
check "a running dunst is stopped, so the bar can take over" "$(grep -c '^pkill -x dunst$' "$TMP/calls")" "1"
check "the link to the install's dunst defaults is removed" \
  "$(exists "$h/.config/dunst/dunstrc.d/10-hyprsimple.conf")" "gone"
check "and the theme colours hyprsimple wrote" "$(exists "$h/.config/dunst/dunstrc.d/90-theme.conf")" "gone"
check "the user's own dunstrc is left" "$(cat "$h/.config/dunst/dunstrc")" "# mine"
check "and their own drop-in" "$(cat "$h/.config/dunst/dunstrc.d/99-mine.conf")" "# my own drop-in"
check "the dunst package is removed" "$(grep -c '^sudo pacman -Rs --noconfirm dunst$' "$TMP/calls")" "1"
check "and it says so" "$(grep -c 'Removed the dunst package' "$TMP/out")" "1"
check "the restart script the old updater may still call is left" \
  "$(exists "$h/.local/bin/hyprsimple-restart-dunst.sh")" "present"
check "and it succeeds" "$(cat "$TMP/rc")" "0"

DUNST_RUNNING="" DUNST_INSTALLED="" migrate "$h"
check "run again with dunst gone, it stops and removes nothing" "$(wc -c <"$TMP/calls" | tr -d ' ')" "0"
check "and succeeds" "$(cat "$TMP/rc")" "0"

h=$(old_home refused)
DUNST_INSTALLED=yes REMOVAL_WORKS=no migrate "$h"
check "a removal pacman refuses does not fail the update" "$(cat "$TMP/rc")" "0"
check "and the command to run by hand is printed" "$(grep -c 'sudo pacman -Rs dunst' "$TMP/out")" "1"

# A binding of the user's own that calls dunstctl.
h=$(old_home own)
printf 'hl.bind("SUPER + H", hl.dsp.exec_cmd("dunstctl history-pop"), { description = "Last" })\n' \
  >>"$h/.config/hypr/bindings/applications.lua"
before=$(cat "$h/.config/hypr/bindings/applications.lua")
DUNST_RUNNING=yes DUNST_INSTALLED=yes migrate "$h"
check "with a binding of your own that calls dunstctl, the package is left installed" \
  "$(grep -c '^sudo ' "$TMP/calls")" "0"
check "the file is named" "$(grep -c 'bindings/applications.lua' "$TMP/out")" "1"
check "and is not rewritten" "$(cat "$h/.config/hypr/bindings/applications.lua")" "$before"
check "dunst is still stopped, since the bar shows the notifications now" \
  "$(grep -c '^pkill -x dunst$' "$TMP/calls")" "1"
check "and it succeeds" "$(cat "$TMP/rc")" "0"

# Without quickshell nothing is taken away. A PATH with no qs on it.
NOQS="$TMP/noqs"; mkdir -p "$NOQS"
for tool in grep rm cat pgrep pkill pacman sudo; do ln -sf "$STUB/$tool" "$NOQS/$tool"; done
h=$(old_home noqs)
MPATH="$NOQS" DUNST_RUNNING=yes DUNST_INSTALLED=yes migrate "$h"
check "without quickshell the migration fails, to run again next time" "$(cat "$TMP/rc")" "1"
check "and stops nothing" "$(wc -c <"$TMP/calls" | tr -d ' ')" "0"
check "and leaves the dunst files in place" \
  "$(exists "$h/.config/dunst/dunstrc.d/90-theme.conf")" "present"

mkdir -p "$TMP/home-bare"
migrate "$TMP/home-bare"
check "a home with nothing of dunst's exits 0" "$(cat "$TMP/rc")" "0"
check "and creates nothing" "$(find "$TMP/home-bare" -mindepth 1 | wc -l | tr -d ' ')" "0"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
