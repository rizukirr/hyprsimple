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

# systemctl was not stubbed before the SERVICES section existed, so the report
# under test would have queried the real user session: the maintainer's units
# would decide whether the checks passed, and on a CI runner with no session
# they would answer differently again. Answers come from files here.
set_failed_user() { printf '%s' "$1" >"$TMP/failed-user"; }
set_failed_system() { printf '%s' "$1" >"$TMP/failed-system"; }
cat >"$STUB/systemctl" <<'STUBEOF'
#!/bin/bash
user=0
[[ ${1:-} == "--user" ]] && { user=1; shift; }
case "${1:-}" in
  --failed)
    if (( user )); then cat "$STATE/failed-user" 2>/dev/null
    else cat "$STATE/failed-system" 2>/dev/null; fi
    ;;
  is-active)
    case "$2" in
      absent.service) echo inactive; exit 4 ;;
      broken.service) echo failed; exit 3 ;;
      *) echo active ;;
    esac
    ;;
  is-enabled)
    case "$2" in
      absent.service) echo not-found; exit 4 ;;
      *) echo enabled ;;
    esac
    ;;
esac
STUBEOF

printf '#!/bin/bash\nexit 0\n' >"$STUB/lspci"; chmod +x "$STUB/lspci"
printf '#!/bin/bash\necho "pacman $*"\n' >"$STUB/pacman"; chmod +x "$STUB/pacman"
printf '#!/bin/bash\necho "git $*"\n' >"$STUB/git"; chmod +x "$STUB/git"

set_journalctl() { printf '%s' "$1" >"$TMP/journal-mode"; }
cat >"$STUB/journalctl" <<'STUBEOF'
#!/bin/bash
case "$(cat "$STATE/journal-mode" 2>/dev/null)" in
  ok)   printf 'a real journal line\n' ;;
  long) seq 1 1000 | sed 's/^/journal line /' ;;
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
# Counted inside the MIGRATIONS section, not across the report. The SERVICES
# section says (none) too when nothing has failed, and a whole-file count
# turned red the moment it was added, for no reason to do with migrations.
check "and all three migration lists do, not just the two that had a fallback" \
  "$(section_body MIGRATIONS | grep -c '^  (none)$')" "3"

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
  "$(section_body MIGRATIONS | grep -c '^  (none)$')" "1"

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

# --- a long section keeps both ends ------------------------------------------
#
# The journal and dmesg sections ended in tail, which keeps the most recent
# lines and drops the beginning. The beginning is where a failure at boot or at
# session start lives, so on a machine with a noisy background service that is
# the wrong half to keep. Measured on this one: a Waydroid container put over
# 300 lines of its own init and libprocessgroup errors into a single boot's
# journal, more than the whole 300 line cap, so anything Hyprland said at
# startup was gone before the report was written.
#
# The helper is exercised directly as well as through the report, because a
# section long enough to truncate is awkward to arrange from a stub and the
# boundary is where this kind of thing goes wrong.
excerpt() {
  bash -c "source <(sed -n '/^head_tail_excerpt()/,/^}/p' '$SCRIPT'); head_tail_excerpt $1"
}

check "input shorter than the cap is passed through whole" \
  "$(seq 1 10 | excerpt 200 | wc -l)" "10"
check "input exactly twice the cap is still whole" \
  "$(seq 1 400 | excerpt 200 | wc -l)" "400"
check "and says nothing about omitting anything, having omitted nothing" \
  "$(seq 1 400 | excerpt 200 | grep -c 'omitted')" "0"

long=$(seq 1 1000 | excerpt 200)
check "one line over the cap does truncate" \
  "$(seq 1 401 | excerpt 200 | grep -c 'omitted from the middle')" "1"
check "the first line survives, which tail alone dropped" \
  "$(printf '%s\n' "$long" | head -n 1)" "1"
check "and so does the last" \
  "$(printf '%s\n' "$long" | tail -n 1)" "1000"
check "the gap is named rather than left silent" \
  "$(printf '%s\n' "$long" | grep -c '600 lines omitted from the middle')" "1"
check "and the whole excerpt stays bounded" \
  "$(printf '%s\n' "$long" | wc -l)" "403"

# Empty input still reaches or_note rather than being reported as a gap.
check "empty input produces nothing for or_note to replace" \
  "$(printf '' | excerpt 200 | wc -c)" "0"

# And through the report itself, on a journal long enough to be cut.
set_journalctl long
report
body=$(section_body 'JOURNAL (this boot, warnings and errors)')
check "a long journal keeps its first line through the report" \
  "$(printf '%s\n' "$body" | head -n 1)" "journal line 1"
check "and its last" \
  "$(printf '%s\n' "$body" | tail -n 1)" "journal line 1000"
check "and says how many it left out" \
  "$(printf '%s\n' "$body" | grep -c 'omitted from the middle')" "1"

# --- the report asks systemd ------------------------------------------------
#
# It asked systemd nothing, which on a systemd desktop leaves out the first
# thing anyone would look at. Found on a live machine: dunst.service had been
# activated over D-Bus before a Wayland display existed, aborted with
# "Couldn't initialize X11 output" five times, hit its start limit and been
# sitting in failed ever since. Notifications kept working, because hyprsimple
# starts its own dunst from autostart, so nothing said so on screen and the
# report would not have either.

set_failed_user ""
set_failed_system ""
report
body=$(section_body SERVICES)
check "with nothing failed, the user list says so" \
  "$(printf '%s\n' "$body" | grep -c '(none)')" "2"

set_failed_user "dunst.service loaded failed failed Dunst notification daemon"
set_failed_system ""
report
body=$(section_body SERVICES)
check "a failed user unit is named" \
  "$(printf '%s\n' "$body" | grep -c 'dunst.service loaded failed failed')" "1"
check "and the system list still says none, so the two are not confused" \
  "$(printf '%s\n' "$body" | grep -c '(none)')" "1"

set_failed_user ""
set_failed_system "thermald.service loaded failed failed Thermal Daemon"
report
body=$(section_body SERVICES)
check "a failed system unit is named too" \
  "$(printf '%s\n' "$body" | grep -c 'thermald.service loaded failed failed')" "1"

# --- and reports the state of the units it depends on -------------------------

set_failed_system ""
report
body=$(section_body SERVICES)
check "the units hyprsimple enables are listed with their state" \
  "$(printf '%s\n' "$body" | grep -c 'hyprpaper.service .*active .*enabled')" "1"
check "including the system ones" \
  "$(printf '%s\n' "$body" | grep -c 'bluetooth.service .*active .*enabled')" "1"

# Every unit install.sh enables has to appear, or the section reports on a
# different set of services from the one the installer sets up.
missing=()
for unit in hyprpaper.service hyprpolkitagent.service battery-monitor.timer \
  pipewire.service wireplumber.service bluetooth.service \
  systemd-resolved.service thermald.service; do
  printf '%s\n' "$body" | grep -q "$unit" || missing+=("$unit")
done
missing_str=""
(( ${#missing[@]} > 0 )) && missing_str="$(printf '%s ' "${missing[@]}")"
check "and none of them is left out" "$missing_str" ""

# --- a machine without systemctl ---------------------------------------------

# Deleting the stub is not enough: the suite's PATH ends in /usr/bin, so the
# real systemctl is still found and the report queries the live session. The
# first version of this check did exactly that and came back holding this
# machine's own failed dunst.service, which is both a wrong answer and a suite
# reading the maintainer's session.
#
# A PATH with no systemctl anywhere on it instead, holding links to the
# commands the report actually runs. The list is asserted below, so a report
# that grows a new dependency fails here rather than silently taking this
# branch for the wrong reason.
MINI="$TMP/minibin"; mkdir -p "$MINI"
# bash included: a variable assignment before a command is in effect while
# the command itself is looked up, so the interpreter has to be on this PATH
# too or the report is never started at all.
for tool in bash mktemp cat date hostname uname find sort grep cut xargs wc head tail sed free git basename; do
  src=$(command -v "$tool" 2>/dev/null) || continue
  ln -sf "$src" "$MINI/$tool"
done
rm -f "$STUB/systemctl"
linked=$(find "$MINI" -maxdepth 1 -type l | wc -l)
if (( linked >= 15 )); then
  pass "built a PATH of $linked commands with no systemctl on it"
else
  fail "linked only $linked commands, so the report would fail for the wrong reason"
fi
check "and systemctl really is unreachable there" \
  "$(PATH="$STUB:$MINI" command -v systemctl >/dev/null 2>&1 && echo found || echo absent)" "absent"

rm -rf "${TMP:?}/fakehome"; mkdir -p "$FAKEHOME"
STATE="$TMP" HOME="$FAKEHOME" HYPRSIMPLE_PATH="$TMP/install" \
  PATH="$STUB:$MINI" bash "$SCRIPT" --print >"$TMP/out" 2>&1
check "a machine with no systemctl says so rather than printing a blank table" \
  "$(section_body SERVICES)" "(systemctl not available)"
check "and the rest of the report still came out" \
  "$(grep -c '^HYPRSIMPLE$' "$TMP/out")" "1"

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
