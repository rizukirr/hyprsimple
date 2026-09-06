#!/bin/bash
# Five sections of the debug report could come out blank and say nothing.
#
# Each was written in this shape:
#
#   find "$state_dir" ... | sort               || echo "  (none)"
#   journalctl -b -p 4..1 ... | tail -n 300    || echo "(unavailable)"
#   sudo dmesg 2>/dev/null | tail -n 200       || echo "(unavailable)"
#
# and not one of those notes could ever be printed. A pipeline's exit status is
# its last command's, and sort and tail succeed on an empty stream whatever
# happened upstream, so the || never fired. A section whose tool was missing,
# or whose sudo went unanswered, came out empty and looked exactly like a
# section with nothing to report.
#
# Measured on a live run where sudo had no terminal to prompt from: the DMESG
# heading was followed by nothing at all, in the one file a user uploads when
# asking for help. Two lines above it, "Skipped after failure:" was equally
# bare, meaning both none skipped and could not tell.
#
# Every command the report shells out to is stubbed here. Nothing reads the
# real journal, the real kernel buffer, or the real package database, and the
# report is pointed at a temporary home throughout.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO/.local/bin/hyprsimple-debug.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the premise, demonstrated rather than asserted --------------------------
#
# If this ever stops holding, every check below is measuring the wrong thing.
#
# Run in a shell with pipefail off, because that is the shell the report runs
# in. This suite sets pipefail for its own sake, and under pipefail the old
# shape does fire its fallback, so demonstrating the bug here without turning
# it off would have proved the opposite of the truth and quietly passed.
premise=$(set +o pipefail; { false | sort || echo "(none)"; } 2>/dev/null)
check "a failing command piped to sort swallows its own fallback" "$premise" ""
premise=$(set +o pipefail; { false | tail -n 3 || echo "(unavailable)"; } 2>/dev/null)
check "and so does one piped to tail, which is why these sections were blank" \
  "$premise" ""
check "and the report is such a shell, setting no pipefail of its own" \
  "$(grep -c pipefail "$SCRIPT")" "0"

# --- stubs -------------------------------------------------------------------

STUB="$TMP/bin"; mkdir -p "$STUB"
FAKEHOME="$TMP/fakehome"

# Absent by default. The report falls back to its own probes for these, and a
# real inxi would spend seconds dumping this machine's hardware into a suite.
for tool in inxi fastfetch hyprctl expac curl ping; do
  printf '#!/bin/bash\nexit 127\n' >"$STUB/$tool"; chmod +x "$STUB/$tool"
done
# command -v has to fail for these, not just the call, so they are removed and
# re-added per case rather than left as failing stubs.
rm -f "$STUB/inxi" "$STUB/fastfetch" "$STUB/hyprctl" "$STUB/expac"

printf '#!/bin/bash\nexit 0\n' >"$STUB/lspci"; chmod +x "$STUB/lspci"
printf '#!/bin/bash\necho "pacman $*"\n' >"$STUB/pacman"; chmod +x "$STUB/pacman"
printf '#!/bin/bash\necho "git $*"\n' >"$STUB/git"; chmod +x "$STUB/git"

set_journalctl() { printf '%s' "$1" >"$TMP/journal-mode"; }
cat >"$STUB/journalctl" <<'STUBEOF'
#!/bin/bash
case "$(cat "$STATE/journal-mode" 2>/dev/null)" in
  ok)   printf 'a real journal line\n' ;;
  *)    echo "journalctl: no journal" >&2; exit 1 ;;
esac
STUBEOF

# dmesg-mode: open (readable with no sudo), restricted (needs sudo), denied
# (sudo cannot get a password either).
set_dmesg() { printf '%s' "$1" >"$TMP/dmesg-mode"; }
cat >"$STUB/dmesg" <<'STUBEOF'
#!/bin/bash
if [[ ${SUDO_RAN:-} == 1 || $(cat "$STATE/dmesg-mode" 2>/dev/null) == open ]]; then
  printf 'a real kernel line\n'
  exit 0
fi
echo "dmesg: read kernel buffer failed: Operation not permitted" >&2
exit 1
STUBEOF
cat >"$STUB/sudo" <<'STUBEOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >>"$STATE/sudo.log"
if [[ $(cat "$STATE/dmesg-mode" 2>/dev/null) == denied ]]; then
  echo "sudo: a terminal is required to read the password" >&2
  exit 1
fi
SUDO_RAN=1 exec "$@"
STUBEOF
chmod +x "$STUB"/*

report() {
  rm -rf "${TMP:?}/fakehome"; mkdir -p "$FAKEHOME"
  rm -f "$TMP/sudo.log"
  STATE="$TMP" HOME="$FAKEHOME" HYPRSIMPLE_PATH="$TMP/install" \
    PATH="$STUB:/usr/bin:/bin" bash "$SCRIPT" --print "$@" >"$TMP/out" 2>&1
}
# The lines of one section, heading and rules excluded.
section_body() {
  awk -v want="$1" '
    $0 == want { inside = 1; next }
    inside && /^=====/ { next }
    inside && /^$/ { next }
    inside && /^[A-Z][A-Z ()a-z,-]*$/ { exit }
    inside { print }
  ' "$TMP/out"
}

# --- migrations: none applied, none skipped, none pending --------------------

mkdir -p "$TMP/install/migrations"
set_journalctl fail
set_dmesg denied

report
mkdir -p "$FAKEHOME/.local/state/hyprsimple/migrations/skipped"
report
check "a home with no migration state says so once, not three times" \
  "$(grep -c 'predates the migration system' "$TMP/out")" "1"

# With the state directory present, all three lists are empty and all three
# used to print a bare heading.
rm -rf "${TMP:?}/fakehome"; mkdir -p "$FAKEHOME/.local/state/hyprsimple/migrations/skipped"
STATE="$TMP" HOME="$FAKEHOME" HYPRSIMPLE_PATH="$TMP/install" \
  PATH="$STUB:/usr/bin:/bin" bash "$SCRIPT" --print >"$TMP/out" 2>&1
check "an empty applied list says (none)" \
  "$(grep -c '^Applied:$' "$TMP/out")" "1"
check "and all three migration lists do, not just the two that had a fallback" \
  "$(grep -c '^  (none)$' "$TMP/out")" "3"

# And the lists still carry their contents when there are any, so the note is
# not simply printed over real output.
: >"$FAKEHOME/.local/state/hyprsimple/migrations/1700000001.sh"
: >"$TMP/install/migrations/1700000002.sh"
STATE="$TMP" HOME="$FAKEHOME" HYPRSIMPLE_PATH="$TMP/install" \
  PATH="$STUB:/usr/bin:/bin" bash "$SCRIPT" --print >"$TMP/out" 2>&1
check "an applied migration is still listed" \
  "$(grep -c '^  1700000001.sh$' "$TMP/out")" "1"
check "a pending one is still listed" \
  "$(grep -c '^  1700000002.sh$' "$TMP/out")" "1"
check "and only the one remaining empty list says (none)" \
  "$(grep -c '^  (none)$' "$TMP/out")" "1"

# --- journal -----------------------------------------------------------------

set_journalctl fail
report
check "a journal that cannot be read says so" \
  "$(section_body 'JOURNAL (this boot, warnings and errors)')" "(unavailable)"

set_journalctl ok
report
check "and a journal that can be read is printed" \
  "$(section_body 'JOURNAL (this boot, warnings and errors)')" "a real journal line"

# --- dmesg -------------------------------------------------------------------

set_journalctl ok

set_dmesg denied
report
body=$(section_body DMESG)
check "dmesg behind a sudo that cannot prompt says it is unavailable" \
  "$(printf '%s' "$body" | grep -c '^(unavailable')" "1"
check "and names the reason, which is the part worth reading" \
  "$(printf '%s' "$body" | grep -c 'terminal is required')" "1"

set_dmesg restricted
report
check "a restricted buffer is read through sudo" \
  "$(section_body DMESG)" "a real kernel line"
check "and sudo really was the thing that got it" \
  "$(grep -c 'sudo dmesg' "$TMP/sudo.log")" "1"

set_dmesg open
report
check "an unrestricted buffer is read directly" \
  "$(section_body DMESG)" "a real kernel line"
check "with no password prompt, sudo never being called" \
  "$([[ -f $TMP/sudo.log ]] && echo called || echo untouched)" "untouched"

report --no-sudo
check "--no-sudo still skips the section by name" \
  "$(section_body DMESG)" "(skipped - --no-sudo)"

# --- the old shape is gone ---------------------------------------------------

code_of() { sed 's/#.*//' "$1"; }
# One pipe with a non-pipe character either side, so the || inside a [[ ]] test
# does not read as a pipeline. The looser pattern counted one.
check "no fallback is left attached to the end of a pipeline" \
  "$(code_of "$SCRIPT" | grep -cE '[^|]\|[^|].*\|\| *echo')" "0"
check "the helper that replaced them is defined" \
  "$(code_of "$SCRIPT" | grep -c '^or_note()')" "1"
check "and is actually used at every one of them" \
  "$(code_of "$SCRIPT" | grep -c '| or_note')" "7"
check "stripping comments leaves the code intact" \
  "$(code_of "$SCRIPT" | grep -c 'journalctl -b')" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
