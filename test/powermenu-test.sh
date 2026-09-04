#!/bin/bash
# The rofi power menu is bound to SUPER + ESCAPE and to the waybar power
# button, and it was adapted from a widely copied menu written for other window
# managers. Two things it inherited did not work here, and nothing had ever run
# it to find out.
#
#   Logout branched on $DESKTOP_SESSION for openbox, bspwm, i3 and plasma, with
#   no other branch. $DESKTOP_SESSION is hyprland-uwsm, so confirming a logout
#   ran nothing.
#
#   Suspend ran `mpc -q pause` and `amixer set Master mute` first. mpc is not
#   installed and is in no package list. The mute worked, measured on a live
#   session as [on] to [off], and nothing undid it, so the machine came back
#   from suspend silent.
#
# The menu is driven here with rofi stubbed, so each selection is exercised for
# what it actually runs.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MENU="$REPO/.config/rofi/powermenu/powermenu.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

STUB="$TMP/bin"
LOG="$TMP/ran.log"
mkdir -p "$STUB"

# Everything the menu can invoke is stubbed and records its own name and
# arguments. A command that is stubbed but never called leaves no line, which
# is how "the suspend path no longer mutes" is checked.
for cmd in hyprshutdown hyprlock systemctl mpc amixer uptime; do
  cat >"$STUB/$cmd" <<STUBEOF
#!/bin/bash
printf '%s %s\n' "$cmd" "\$*" >>"$LOG"
STUBEOF
  chmod +x "$STUB/$cmd"
done
# uptime is read for the menu header, so it has to say something.
printf '#!/bin/bash\necho "up 1 hour"\n' >"$STUB/uptime"
chmod +x "$STUB/uptime"

# hyprsimple's logout script, stubbed where the menu looks for it.
FAKE_HOME="$TMP/home"
mkdir -p "$FAKE_HOME/.local/bin" "$FAKE_HOME/.config/rofi"
cat >"$FAKE_HOME/.local/bin/hypr-logout.sh" <<STUBEOF
#!/bin/bash
printf 'hypr-logout.sh\n' >>"$LOG"
STUBEOF
chmod +x "$FAKE_HOME/.local/bin/hypr-logout.sh"

# rofi is called twice: once for the menu, once to confirm. The first call
# answers with the glyph under test and the second with the confirmation.
make_rofi() {
  local choice="$1" confirm="$2"
  cat >"$STUB/rofi" <<STUBEOF
#!/bin/bash
state="$TMP/rofi.state"
if [[ ! -f \$state ]]; then
  printf '1\n' >"\$state"
  printf '%s\n' "$choice"
else
  printf '%s\n' "$confirm"
fi
STUBEOF
  chmod +x "$STUB/rofi"
  rm -f "$TMP/rofi.state"
}

# The glyphs are read out of the menu itself rather than retyped, so a suite
# that drifts from the script fails instead of silently testing nothing.
glyph() { sed -n "s/^$1='\(.*\)'$/\1/p" "$MENU"; }

for name in shutdown reboot lock suspend logout yes no; do
  if [[ -n $(glyph "$name") ]]; then
    pass "the '$name' glyph was read out of the menu"
  else
    fail "could not read the '$name' glyph from the menu, so every check below is testing nothing"
    exit 1
  fi
done

# Three of these are BMP private use area codepoints, which do not survive
# every editor and every pipeline. Two of them going empty would put two empty
# patterns in the menu's final case, the first would win, and choosing logout
# would silently lock the screen instead. An empty glyph for yes is worse: the
# confirmation would match anything.
# LC_ALL=C, so sort compares bytes. Under a UTF-8 locale these private use
# codepoints have no collation weight and compare equal to each other, so
# `sort -u` reduced seven distinct glyphs to three and this check failed
# against a file that was perfectly correct.
distinct=$(for name in shutdown reboot lock suspend logout yes no; do glyph "$name"; done |
  LC_ALL=C sort -u | grep -c .)
check "all seven glyphs are distinct, so no two menu entries collide" "$distinct" "7"

run_menu() {
  : >"$LOG"
  make_rofi "$1" "$2"
  HOME="$FAKE_HOME" PATH="$STUB:$PATH" DESKTOP_SESSION=hyprland-uwsm \
    bash "$MENU" >/dev/null 2>&1
  cat "$LOG" 2>/dev/null
}

# ---- logout actually logs out --------------------------------------------

out="$(run_menu "$(glyph logout)" "$(glyph yes)")"
check "confirming a logout runs hyprsimple's logout script" \
  "$(printf '%s' "$out" | grep -c 'hypr-logout.sh')" "1"
check "and it is the only thing it runs" \
  "$(printf '%s' "$out" | grep -vc 'hypr-logout.sh\|^uptime')" "0"

out="$(run_menu "$(glyph logout)" "$(glyph no)")"
check "declining a logout runs nothing" \
  "$(printf '%s' "$out" | grep -c 'hypr-logout.sh')" "0"

# ---- suspend suspends and nothing else -----------------------------------

out="$(run_menu "$(glyph suspend)" "$(glyph yes)")"
check "confirming a suspend suspends" \
  "$(printf '%s' "$out" | grep -c '^systemctl suspend')" "1"
check "and does not mute the audio" \
  "$(printf '%s' "$out" | grep -c '^amixer')" "0"
check "and does not reach for mpd, which is not installed" \
  "$(printf '%s' "$out" | grep -c '^mpc')" "0"

# ---- the rest still work --------------------------------------------------

out="$(run_menu "$(glyph shutdown)" "$(glyph yes)")"
check "confirming a shutdown shuts down" \
  "$(printf '%s' "$out" | grep -c 'hyprshutdown.*Shutting down')" "1"

out="$(run_menu "$(glyph reboot)" "$(glyph yes)")"
check "confirming a reboot reboots" \
  "$(printf '%s' "$out" | grep -c 'hyprshutdown.*Restarting')" "1"

out="$(run_menu "$(glyph shutdown)" "$(glyph no)")"
check "declining a shutdown does nothing" \
  "$(printf '%s' "$out" | grep -c 'hyprshutdown')" "0"

# lock is the one entry that does not confirm, by design
out="$(run_menu "$(glyph lock)" "$(glyph no)")"
check "lock locks without asking for confirmation" \
  "$(printf '%s' "$out" | grep -c '^hyprlock')" "1"

# ---- no branch on a window manager this project does not run -------------

# Comment lines are stripped first: the header documents the branches that were
# removed, and naming them there is the point.
check "the menu no longer branches on DESKTOP_SESSION" \
  "$(grep -v '^[[:space:]]*#' "$MENU" | grep -cE 'openbox|bspwm|i3-msg|ksmserver')" "0"

# ---- the migration delivers it to existing installs -----------------------
#
# powermenu.sh lives in ~/.config and is never overwritten by an update, so
# without a migration the fix reaches nobody who already has hyprsimple.

MIGRATION="$REPO/migrations/1788536332.sh"
if [[ -f $MIGRATION ]]; then
  pass "the migration this suite tests exists"
else
  fail "$MIGRATION is missing, so every check below is testing nothing"
fi

# The fixture is a version the project really shipped, kept as a file rather
# than read from git history, because CI checks out shallow and the commit is
# not there. Checked against the migration's own list so it cannot rot into
# bytes no user ever had. Retyping it was never an option: three of its glyphs
# are private use codepoints that do not survive a round trip through an editor.
PREVIOUS="$REPO/test/fixtures/rofi/powermenu.pre-fix.sh"
previous_sum="$(md5sum "$PREVIOUS" 2>/dev/null | cut -d' ' -f1)"

check "the fixture is a version the migration claims to handle" \
  "$(grep -c "$previous_sum" "$MIGRATION")" "1"

run_migration() {
  HOME="$1" HYPRSIMPLE_PATH="$REPO" bash "$MIGRATION" 2>&1
}
seed() {
  local home="$TMP/$1"
  rm -rf "$home"
  mkdir -p "$home/.config/rofi/powermenu"
  cp "$PREVIOUS" "$home/.config/rofi/powermenu/powermenu.sh"
  printf '%s' "$home"
}

home="$(seed pristine)"
run_migration "$home" >/dev/null
check "a never-edited power menu is replaced" \
  "$(cmp -s "$home/.config/rofi/powermenu/powermenu.sh" "$MENU" && echo replaced || echo unchanged)" \
  "replaced"
check "and the old one is kept as a backup" \
  "$(cmp -s "$home/.config/rofi/powermenu/powermenu.sh.bak" "$PREVIOUS" && echo kept || echo lost)" "kept"

home="$(seed edited)"
printf '\n# MY OWN EDIT\n' >>"$home/.config/rofi/powermenu/powermenu.sh"
out="$(run_migration "$home")"
check "an edited power menu is left alone" \
  "$(grep -c 'MY OWN EDIT' "$home/.config/rofi/powermenu/powermenu.sh")" "1"
check "and the user is told how to update it" \
  "$(printf '%s' "$out" | grep -c 'hyprsimple-refresh-config.sh rofi/powermenu/powermenu.sh')" "1"

home="$(seed current)"
cp "$MENU" "$home/.config/rofi/powermenu/powermenu.sh"
out="$(run_migration "$home")"
check "an already-current power menu is a no-op" \
  "$([[ -f $home/.config/rofi/powermenu/powermenu.sh.bak ]] && echo backed-up || echo untouched)" "untouched"
check "and is not accused of having edits" \
  "$(printf '%s' "$out" | grep -c 'your own edits')" "0"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
