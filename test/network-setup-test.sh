#!/bin/bash
# Checks the move from iwd to NetworkManager, which the bar's network panel
# needs: what is copied, what is stopped and started, and that it is undone
# when the network does not come back.
#
# Nothing here touches a real service, a real network or a real password.
# systemctl, sudo, ip, nmcli and sleep are stand-ins, the services are files in
# a directory of this suite's own, and so are iwd's networks and
# NetworkManager's connections. The PATH holds only the stand-ins and the plain
# tools linked in by name.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/.local/bin/hyprsimple-network-setup.sh"
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
STUB="$TMP/stub"; mkdir -p "$STUB"
for tool in find sort sed head grep install test cat rm; do
  ln -sf "$(command -v "$tool")" "$STUB/$tool"
done

# A service is a file: active-<unit> while it runs, enabled-<unit> while it is
# enabled. Stopping iwd takes the network down. Starting it brings it back, and
# so does starting NetworkManager when $NM_BRINGS_NETWORK says it would.
cat >"$STUB/systemctl" <<'STUBEOF'
#!/bin/bash
verb="$1"; shift
units=()
for a in "$@"; do [[ $a == -* ]] || units+=("${a%.service}"); done
case "$verb" in
is-active) [[ -e $STATE/active-${units[0]} ]] ;;
is-enabled) [[ -e $STATE/enabled-${units[0]} ]] ;;
disable)
  for u in "${units[@]}"; do
    printf 'disable %s\n' "$u" >>"$CALLS"
    rm -f "$STATE/active-$u" "$STATE/enabled-$u"
    [[ $u == iwd ]] && rm -f "$STATE/online"
    [[ $u == NetworkManager ]] && rm -f "$STATE/online"
  done
  ;;
enable)
  for u in "${units[@]}"; do
    printf 'enable %s\n' "$u" >>"$CALLS"
    [[ $u == NetworkManager && ${NM_STARTS:-yes} != yes ]] && exit 1
    : >"$STATE/active-$u"; : >"$STATE/enabled-$u"
    [[ $u == iwd ]] && : >"$STATE/online"
    [[ $u == NetworkManager && ${NM_BRINGS_NETWORK:-yes} == yes ]] && : >"$STATE/online"
  done
  # The last test above is false for most units, and must not be the answer.
  exit 0
  ;;
esac
STUBEOF
# sudo runs what it is given, which is only ever a stand-in or a plain tool
# working on this suite's own directories.
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
"$@"
STUBEOF
cat >"$STUB/ip" <<'STUBEOF'
#!/bin/bash
[[ -e $STATE/online ]] && echo "default via 192.0.2.1 dev wlan0"
exit 0
STUBEOF
printf '#!/bin/bash\nexit 0\n' >"$STUB/nmcli"
printf '#!/bin/bash\nexit 0\n' >"$STUB/sleep"
chmod +x "$STUB"/systemctl "$STUB"/sudo "$STUB"/ip "$STUB"/nmcli "$STUB"/sleep
for tool in systemctl sudo ip; do
  check "the real $tool is unreachable from here" "$(PATH="$STUB" command -v "$tool")" "$STUB/$tool"
done

# A machine: which services run, and whether it is online.
machine() {
  local name="$1"; shift
  M="$TMP/$name"; STATE="$M/state"
  mkdir -p "$STATE" "$M/iwd" "$M/nm"
  local unit
  for unit in "$@"; do
    if [[ $unit == online ]]; then : >"$STATE/online"
    else : >"$STATE/active-$unit"; : >"$STATE/enabled-$unit"; fi
  done
}
run() {
  : >"$M/calls"
  env -i PATH="${RUN_PATH:-$STUB}" STATE="$STATE" CALLS="$M/calls" \
    HYPRSIMPLE_IWD_DIR="$M/iwd" HYPRSIMPLE_NM_DIR="$M/nm" HYPRSIMPLE_NETWORK_WAIT=3 \
    NM_STARTS="${NM_STARTS:-yes}" NM_BRINGS_NETWORK="${NM_BRINGS_NETWORK:-yes}" \
    SSH_CONNECTION="${SSH:-}" "$BASH_BIN" "$SCRIPT" "$@" >"$M/out" 2>&1
  printf '%s' "$?" >"$M/rc"
}
is() { [[ -e $STATE/$1 ]] && echo yes || echo no; }

# ---- a machine that already runs NetworkManager ---------------------------------

machine nm NetworkManager online
printf '[Security]\nPassphrase=secret\n' >"$M/iwd/Old.psk"
run
check "a machine on NetworkManager is left alone" "$(wc -c <"$M/calls" | tr -d ' ')" "0"
check "and nothing is copied into it" "$(find "$M/nm" -type f | wc -l | tr -d ' ')" "0"
check "and it succeeds" "$(cat "$M/rc")" "0"

# ---- a machine that runs iwd ----------------------------------------------------

machine iwd iwd systemd-networkd online
printf '[Security]\nPassphrase=correct horse\n' >"$M/iwd/Home.psk"
printf '[Security]\nPreSharedKey=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef\n' >"$M/iwd/Office.psk"
printf '[Settings]\nAutoConnect=true\n' >"$M/iwd/Cafe.open"
printf '[Security]\nEAP-Method=PEAP\n' >"$M/iwd/Campus.8021x"
# "My Net!" as iwd names a network with characters it keeps out of a file name.
printf '[Security]\nPassphrase= lead\\\\ing\n' >"$M/iwd/=4d79204e657421.psk"
: >"$M/iwd/notes.txt"
run
check "iwd is stopped and disabled" "$(is active-iwd)$(is enabled-iwd)" "nono"
check "and systemd-networkd with it, since two would fight over one interface" \
  "$(is active-systemd-networkd)" "no"
check "NetworkManager is started and enabled" "$(is active-NetworkManager)$(is enabled-NetworkManager)" "yesyes"
check "the old services go before NetworkManager comes" \
  "$(grep -n 'disable iwd\|enable NetworkManager' "$M/calls" | cut -d: -f2 | paste -sd,)" \
  "disable iwd,enable NetworkManager"
check "it says the move worked" "$(grep -c 'NetworkManager runs the network now' "$M/out")" "1"
check "and how to go back" "$(grep -c 'systemctl enable --now iwd' "$M/out")" "1"
check "and it succeeds" "$(cat "$M/rc")" "0"

home="$M/nm/hyprsimple-iwd-Home.nmconnection"
check "a network with a passphrase is copied with it" "$(grep -cx 'psk=correct horse' "$home")" "1"
check "under its own name" "$(grep -cx 'ssid=Home' "$home")" "1"
check "as a WPA network" "$(grep -cx 'key-mgmt=wpa-psk' "$home")" "1"
check "in a file only root can read" "$(stat -c '%a' "$home")" "600"
check "a network iwd kept only the derived key for is copied with that" \
  "$(grep -c '^psk=0123456789abcdef' "$M/nm/hyprsimple-iwd-Office.nmconnection")" "1"
check "an open network is copied without a security section" \
  "$(grep -c 'wifi-security' "$M/nm/hyprsimple-iwd-Cafe.nmconnection")" "0"
check "and still names its network" "$(grep -cx 'ssid=Cafe' "$M/nm/hyprsimple-iwd-Cafe.nmconnection")" "1"
odd="$M/nm/hyprsimple-iwd-=4d79204e657421.nmconnection"
check "a name iwd wrote in hex is written as its bytes" \
  "$(grep -cx 'ssid=77;121;32;78;101;116;33;' "$odd")" "1"
check "and a password with a leading space and a backslash is escaped for the keyfile" \
  "$(grep -cxF 'psk=\slead\\\\ing' "$odd")" "1"
check "an enterprise network is not copied" "$(find "$M/nm" -name '*Campus*' | wc -l | tr -d ' ')" "0"
check "and is named, so it can be set up again" "$(grep -c 'Not copied: Campus' "$M/out")" "1"
check "a file that is not a network is ignored" "$(find "$M/nm" -type f | wc -l | tr -d ' ')" "4"
check "the count is said" "$(grep -c 'Copied 4 Wi-Fi network' "$M/out")" "1"
check "no password is passed on a command line" "$(grep -c 'correct horse' "$M/calls")" "0"
check "iwd's own files are all still there" "$(find "$M/iwd" -type f | wc -l | tr -d ' ')" "6"

# Run again: NetworkManager runs now, so nothing more happens.
before=$(cat "$home")
run
check "running it again changes nothing" "$(wc -c <"$M/calls" | tr -d ' ')" "0"
check "and the copied network is as it was" "$(cat "$home")" "$before"

# A connection NetworkManager already has under that name is not overwritten.
machine keep iwd online
printf '[Security]\nPassphrase=new\n' >"$M/iwd/Home.psk"
printf 'mine\n' >"$M/nm/hyprsimple-iwd-Home.nmconnection"
run
check "a connection already there is left as it is" "$(cat "$M/nm/hyprsimple-iwd-Home.nmconnection")" "mine"

# ---- the network does not come back ---------------------------------------------

machine dead iwd online
printf '[Security]\nPassphrase=secret\n' >"$M/iwd/Home.psk"
NM_BRINGS_NETWORK=no run
check "when the network does not come back, NetworkManager is stopped again" \
  "$(is active-NetworkManager)$(is enabled-NetworkManager)" "nono"
check "and iwd is started and enabled again" "$(is active-iwd)$(is enabled-iwd)" "yesyes"
check "which puts the machine back online" "$(is online)" "yes"
check "it says the move was undone" "$(grep -c 'the move is undone' "$M/out")" "1"
check "and how to try by hand" "$(grep -c 'hyprsimple-network-setup.sh' "$M/out")" "1"
check "and does not fail the update over it" "$(cat "$M/rc")" "0"

machine nostart iwd systemd-networkd online
NM_STARTS=no run
check "when NetworkManager will not start, every old service is started again" \
  "$(is active-iwd)$(is active-systemd-networkd)" "yesyes"
check "and it says so" "$(grep -c 'would not start' "$M/out")" "1"
check "without failing" "$(cat "$M/rc")" "0"

# A machine that was offline has nothing to come back to, so it is not judged.
machine offline iwd
NM_BRINGS_NETWORK=no run
check "a machine that was offline to begin with is moved and not undone" \
  "$(is active-NetworkManager)$(is active-iwd)" "yesno"

# ---- machines it leaves alone ---------------------------------------------------

machine other systemd-networkd online
run
check "a machine with neither NetworkManager nor iwd is left alone" "$(wc -c <"$M/calls" | tr -d ' ')" "0"
check "and told what the panel needs" "$(grep -c 'needs NetworkManager' "$M/out")" "1"
check "and it succeeds" "$(cat "$M/rc")" "0"

machine ssh iwd online
SSH="192.0.2.7 50000 192.0.2.8 22" run
check "over SSH nothing is moved, since it would cut the session" "$(wc -c <"$M/calls" | tr -d ' ')" "0"
check "and iwd still runs" "$(is active-iwd)" "yes"
check "and it says where to run it" "$(grep -c 'Run this at the machine itself' "$M/out")" "1"
SSH="192.0.2.7 50000 192.0.2.8 22" run --force
check "--force moves it over SSH anyway" "$(is active-NetworkManager)" "yes"

# Without NetworkManager installed nothing is touched. A PATH with no nmcli.
NONM="$TMP/nonm"; mkdir -p "$NONM"
for tool in "$STUB"/*; do [[ ${tool##*/} == nmcli ]] || ln -sf "$tool" "$NONM/${tool##*/}"; done
machine missing iwd online
RUN_PATH="$NONM" run
check "without NetworkManager installed it fails, to be tried again" "$(cat "$M/rc")" "1"
check "and touches nothing" "$(wc -c <"$M/calls" | tr -d ' ')$(is active-iwd)" "0yes"
check "and says what to install" "$(grep -c 'pacman -S networkmanager' "$M/out")" "1"

# ---- where it is called from ----------------------------------------------------

check "networkmanager is installed with hyprsimple" "$(grep -cx 'networkmanager' "$REPO/packages.txt")" "1"
check "install.sh runs the move" \
  "$(sed 's/^[[:space:]]*#.*//' "$REPO/install.sh" | grep -c 'hyprsimple-network-setup.sh" || true')" "1"
# After the installer's closing summary, which is after everything that needs
# the network, so an install is never cut off part way.
summary_line=$(grep -n '^echo "Log saved to \$INSTALL_LOG"' "$REPO/install.sh" | cut -d: -f1)
move_line=$(grep -n 'hyprsimple-network-setup.sh" || true' "$REPO/install.sh" | cut -d: -f1)
check "and only after its closing summary, when nothing more needs the network" \
  "$((move_line > summary_line))" "1"

MIGRATION="$(grep -l 'Run the network with NetworkManager' "$REPO"/migrations/*.sh | head -1)"
check "the migration was found" "$([[ -n $MIGRATION ]] && echo found || echo missing)" "found"

# The migration against the real script, on a machine of this suite's own.
migrate() {
  : >"$M/calls"
  mkdir -p "$M/home/.local/bin"
  [[ ${NO_SCRIPT:-} == yes ]] || cp "$SCRIPT" "$M/home/.local/bin/"
  env -i PATH="${RUN_PATH:-$STUB}" HOME="$M/home" STATE="$STATE" CALLS="$M/calls" \
    HYPRSIMPLE_IWD_DIR="$M/iwd" HYPRSIMPLE_NM_DIR="$M/nm" HYPRSIMPLE_NETWORK_WAIT=3 \
    "$BASH_BIN" "$MIGRATION" >"$M/out" 2>&1
  printf '%s' "$?" >"$M/rc"
}
ln -sf "$(command -v cp)" "$STUB/cp"

machine mig-iwd iwd online
printf '[Security]\nPassphrase=secret\n' >"$M/iwd/Home.psk"
migrate
check "the migration moves a machine on iwd" "$(is active-NetworkManager)$(is active-iwd)" "yesno"
check "with its network" "$(grep -cx 'psk=secret' "$M/nm/hyprsimple-iwd-Home.nmconnection")" "1"
check "and succeeds" "$(cat "$M/rc")" "0"

machine mig-nm NetworkManager online
migrate
check "the migration leaves a machine on NetworkManager alone" "$(wc -c <"$M/calls" | tr -d ' ')" "0"
check "and succeeds" "$(cat "$M/rc")" "0"

machine mig-nonm iwd online
RUN_PATH="$NONM" migrate
check "without NetworkManager installed the migration fails, to run again next time" "$(cat "$M/rc")" "1"
check "and iwd still runs" "$(is active-iwd)" "yes"

machine mig-noscript iwd online
NO_SCRIPT=yes migrate
check "without the script the migration fails and touches nothing" \
  "$(cat "$M/rc")$(wc -c <"$M/calls" | tr -d ' ')" "10"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
