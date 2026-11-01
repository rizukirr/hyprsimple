#!/bin/bash
# Checks hyprsimple-session.sh against a directory of its own.
#
# The script writes one file under /usr/local/share/wayland-sessions and uses
# sudo when it cannot write there itself. Here HYPRSIMPLE_SESSION_DIR points at
# a temporary directory the user owns, and the sudo on PATH is a stub that
# records the call and fails, so a run that reached for sudo fails loudly and
# nothing outside the temporary directory is touched.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/.local/bin/hyprsimple-session.sh"
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
CALL_LOG="$TMP/calls"; export CALL_LOG
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALL_LOG"
exit 1
STUBEOF
chmod +x "$STUB/sudo"
export PATH="$STUB:$PATH"

SESSIONS="$TMP/wayland-sessions"
export HYPRSIMPLE_SESSION_DIR="$SESSIONS"
ENTRY="$SESSIONS/hyprsimple.desktop"
EXEC_LINE='Exec=uwsm start -e -D Hyprland:Hyprsimple -N Hyprsimple hyprland.desktop'

sudo_calls() { if [[ -f $CALL_LOG ]]; then grep -c . "$CALL_LOG"; else echo 0; fi; }

# ---- add -----------------------------------------------------------------
out=$("$SCRIPT" 2>&1); status=$?
check "adding exits 0" "$status" "0"
check "the entry file exists" "$([[ -f $ENTRY ]] && echo yes || echo no)" "yes"
check "it carries the uwsm Exec line" "$(grep -cxF "$EXEC_LINE" "$ENTRY")" "1"
check "it names uwsm in TryExec" "$(grep -cx 'TryExec=uwsm' "$ENTRY")" "1"
check "it is named Hyprsimple" "$(grep -cx 'Name=Hyprsimple' "$ENTRY")" "1"
check "the output names the file" "$(grep -cF "$ENTRY" <<<"$out")" "1"

# ---- add again -----------------------------------------------------------
before=$(cat "$ENTRY")
out=$("$SCRIPT" 2>&1); status=$?
check "adding again exits 0" "$status" "0"
check "and leaves the file as it was" "$(cat "$ENTRY")" "$before"
check "and says it is already there" "$(grep -ci 'already' <<<"$out")" "1"

# ---- remove --------------------------------------------------------------
out=$("$SCRIPT" remove 2>&1); status=$?
check "removing exits 0" "$status" "0"
check "the entry file is gone" "$([[ -e $ENTRY ]] && echo yes || echo no)" "no"
check "the directory is still there" "$([[ -d $SESSIONS ]] && echo yes || echo no)" "yes"

# ---- remove again --------------------------------------------------------
out=$("$SCRIPT" remove 2>&1); status=$?
check "removing again exits 0" "$status" "0"
check "and says there is nothing to remove" "$(grep -ci 'nothing to remove' <<<"$out")" "1"

# ---- bad argument --------------------------------------------------------
"$SCRIPT" nonsense >/dev/null 2>&1; status=$?
check "an unknown argument exits 1" "$status" "1"
check "and writes nothing" "$([[ -e $ENTRY ]] && echo yes || echo no)" "no"

# ---- sudo ----------------------------------------------------------------
check "sudo was never reached" "$(sudo_calls)" "0"

# ---- the directory does not exist yet -----------------------------------
rm -rf "${SESSIONS:?}"
"$SCRIPT" >/dev/null 2>&1; status=$?
check "adding creates the directory" "$status" "0"
check "and the file inside it" "$([[ -f $ENTRY ]] && echo yes || echo no)" "yes"
check "still without sudo" "$(sudo_calls)" "0"

# ---- install.sh ----------------------------------------------------------
# --help exits inside the argument loop, before the log, the sudo prompt and
# the Arch check, so it is safe to run on any machine.
help_out=$(bash "$REPO/install.sh" --help 2>&1); status=$?
check "install.sh --help exits 0" "$status" "0"
check "and documents --session-entry" \
  "$(grep -q -- '--session-entry' <<<"$help_out" && echo yes || echo no)" "yes"
check "install.sh calls the script with a fallthrough, not a hard failure" \
  "$(grep -cF '"$HOME/.local/bin/hyprsimple-session.sh" ||' "$REPO/install.sh")" "1"
check "and only when the flag was given" \
  "$(grep -cE '^if \[\[ \$SESSION_ENTRY == 1 \]\]; then$' "$REPO/install.sh")" "1"

# ---- a write that does not land ------------------------------------------
# A sudo that says yes and writes nothing, the shape of a sudo that was
# refused or a tee that failed. The script has to notice and say so itself,
# without cat's own complaint landing first.
LOCKED="$TMP/locked"; mkdir -p "$LOCKED"; chmod 555 "$LOCKED"
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$CALL_LOG"
exit 0
STUBEOF
err=$(HYPRSIMPLE_SESSION_DIR="$LOCKED/wayland-sessions" "$SCRIPT" 2>&1 >/dev/null); status=$?
check "a write that does not land exits 1" "$status" "1"
check "and reports it in one line of its own" "$(printf '%s\n' "$err" | grep -c .)" "1"
check "that names the file" "$(grep -cF 'wayland-sessions/hyprsimple.desktop' <<<"$err")" "1"
check "after going through sudo" "$(grep -c '^sudo tee ' "$CALL_LOG")" "1"
chmod 755 "$LOCKED"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
