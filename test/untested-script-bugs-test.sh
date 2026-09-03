#!/bin/bash
# Six defects found in scripts no suite had ever run. Five are one shape: an
# error discarded, then success reported anyway. This suite drives each failure
# path with stubs, so nothing here touches wifi, cpu governors, or the network.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"; mkdir -p "$STUB"
LOG="$TMP/calls"
stub_logging() {
  cat >"$STUB/$1" <<STUBEOF
#!/bin/bash
printf '%s %s\n' "$1" "\$*" >>"\$CALL_LOG"
exit ${2:-0}
STUBEOF
  chmod +x "$STUB/$1"
}

# search_by_keyword.sh printed its usage and then searched anyway. rg treats an
# empty pattern as matching every line of every file, so `sk` with no argument
# fed the whole tree to fzf.
stub_logging rg; stub_logging fzf
: >"$LOG"
CALL_LOG="$LOG" PATH="$STUB:$PATH" bash "$BIN/search_by_keyword.sh" >/dev/null 2>&1
check "search_by_keyword with no argument exits non-zero" "$?" "1"
check "search_by_keyword with no argument runs nothing" \
  "$(wc -l <"$LOG" | tr -d ' ')" "0"

: >"$LOG"
CALL_LOG="$LOG" PATH="$STUB:$PATH" bash "$BIN/search_by_keyword.sh" needle >/dev/null 2>&1
check "search_by_keyword with an argument still searches" \
  "$(grep -c '^rg .*needle' "$LOG")" "1"

# wifi-powersave.sh sent iw's output to /dev/null and notified success either
# way. iw exits 2 on a value it rejects and 1 on a missing one.
stub_logging sudo 0
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
# Stands in for sudo by running the rest of the line, so the iw stub decides.
exec "$@"
STUBEOF
chmod +x "$STUB/sudo"
stub_logging notify-send

# A fake sysfs holding one wireless interface, so this runs the same way on a
# laptop and on a runner that has no wireless hardware at all.
mkdir -p "$TMP/net/wlan0/wireless" "$TMP/net/eth0"

stub_logging iw 1
: >"$LOG"
CALL_LOG="$LOG" HYPRSIMPLE_SYSFS_NET="$TMP/net" PATH="$STUB:$PATH" bash "$BIN/wifi-powersave.sh" on >/dev/null 2>&1
rc=$?
check "wifi-powersave exits non-zero when iw fails" "$rc" "1"
check "wifi-powersave does not announce success when iw fails" \
  "$(grep -c 'notify-send.*Power save: on' "$LOG")" "0"
check "wifi-powersave says so when it could not set it" \
  "$(grep -c 'notify-send.*Could not set power save' "$LOG")" "1"

stub_logging iw 0
: >"$LOG"
CALL_LOG="$LOG" HYPRSIMPLE_SYSFS_NET="$TMP/net" PATH="$STUB:$PATH" bash "$BIN/wifi-powersave.sh" on >/dev/null 2>&1
check "wifi-powersave announces success when iw succeeds" \
  "$(grep -c 'notify-send.*Power save: on' "$LOG")" "1"

: >"$LOG"
CALL_LOG="$LOG" HYPRSIMPLE_SYSFS_NET="$TMP/net" PATH="$STUB:$PATH" bash "$BIN/wifi-powersave.sh" onn >/dev/null 2>&1
check "wifi-powersave rejects a value that is not on or off" "$?" "1"
check "wifi-powersave runs no iw for a bad value" \
  "$(grep -c '^iw ' "$LOG")" "0"

# toggle_cpu_mode.sh echoed the mode whether or not cpupower set it.
stub_logging cpupower 1
: >"$LOG"
CALL_LOG="$LOG" PATH="$STUB:$PATH" bash "$BIN/toggle_cpu_mode.sh" on >"$TMP/out" 2>/dev/null
check "toggle_cpu_mode exits non-zero when cpupower fails" "$?" "1"
check "toggle_cpu_mode does not claim a mode it failed to set" \
  "$(grep -c '^CPU: performance$' "$TMP/out")" "0"

stub_logging cpupower 0
CALL_LOG="$LOG" PATH="$STUB:$PATH" bash "$BIN/toggle_cpu_mode.sh" on >"$TMP/out" 2>/dev/null
check "toggle_cpu_mode reports the mode when cpupower succeeds" \
  "$(grep -c '^CPU: performance$' "$TMP/out")" "1"

# hyprsimple-debug.sh's upload tested the response for emptiness, which cannot
# tell a URL from an error message, and curl without --fail exits 0 on an HTTP
# error and prints the body. The function is lifted rather than the script run,
# because collecting a real log invokes journalctl and sudo.
sed -n '/^upload()/,/^}/p' "$BIN/hyprsimple-debug.sh" >"$TMP/upload.sh"
check "upload was lifted out of hyprsimple-debug.sh" \
  "$(grep -c '^upload()' "$TMP/upload.sh")" "1"
# shellcheck disable=SC1091
. "$TMP/upload.sh"
LOG_FILE="$TMP/fake.log"; : >"$LOG_FILE"

printf '#!/bin/bash\necho "Rate limit exceeded" >&2\nexit 22\n' >"$STUB/curl"; chmod +x "$STUB/curl"
out=$(PATH="$STUB:$PATH" upload 2>&1); rc=$?
check "a failed upload exits non-zero" "$rc" "1"
check "a failed upload is not announced as a link" \
  "$(grep -c 'Share this link' <<<"$out")" "0"

printf '#!/bin/bash\necho "Rate limit exceeded"\nexit 0\n' >"$STUB/curl"; chmod +x "$STUB/curl"
out=$(PATH="$STUB:$PATH" upload 2>&1); rc=$?
check "a 200 carrying something that is not a URL is not announced as a link" \
  "$(grep -c 'Share this link' <<<"$out")" "0"

printf '#!/bin/bash\necho "https://0x0.st/abc.txt"\n' >"$STUB/curl"; chmod +x "$STUB/curl"
out=$(PATH="$STUB:$PATH" upload 2>&1)
check "a real URL is announced as a link" \
  "$(grep -c 'https://0x0.st/abc.txt' <<<"$out")" "1"

# The log path was a fixed name in a world-writable directory, truncated with >.
check "the debug log path is generated, not fixed" \
  "$(grep -c 'LOG_FILE="/tmp/hyprsimple-debug.log"' "$BIN/hyprsimple-debug.sh")" "0"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
