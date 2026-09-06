#!/bin/bash
# Three symlinks carry every install-owned default into ~/.config, and only
# install.sh ever made them.
#
#   ~/.config/hypr/hyprsimple                  hyprlock, hypridle, xdph
#   ~/.config/rofi/hyprsimple                  the rofi stubs
#   ~/.config/dunst/dunstrc.d/10-hyprsimple.conf   dunst's drop-in
#
# hyprsimple-update refreshed the helper scripts on every run and never looked
# at these, so a link deleted, or left pointing at an old HYPRSIMPLE_PATH,
# stayed broken through every update there would ever be.
#
# It stays broken quietly. hyprlang ignores a `source =` naming a file that is
# not there and rofi ignores a missing @import, both without a word: measured
# with hyprsunset and `rofi -dump-theme`, each exits 0 and prints nothing. So a
# missing hypr link leaves hypridle.conf with nothing but five ignored source
# lines, which is no listeners at all, which is a screen that stops dimming,
# locking and suspending on idle with nothing anywhere to say why.
#
# The dangling-link case is not hypothetical: migration 1788620441 exists
# because rofi links had already been left dangling once.
#
# Nothing here runs the updater. ensure_link is taken out of it and exercised
# against throwaway directories.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO/.local/bin/hyprsimple-update.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the function, taken from the updater so it cannot drift from it ---------

fn=$(sed -n '/^ensure_link() {/,/^}/p' "$UPDATE")
if [[ $(printf '%s\n' "$fn" | grep -c .) -lt 10 ]]; then
  fail "extracted $(printf '%s\n' "$fn" | grep -c .) lines of ensure_link, so this is reading the wrong thing"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "extracted ensure_link from the updater"

TARGET="$TMP/install/default/hypr"
mkdir -p "$TARGET"
: >"$TARGET/hyprlock.conf"

# Runs ensure_link with colours emptied, so the messages are plain text.
run_link() {
  bash -c "
    GREEN=; YELLOW=; NC=
    $fn
    ensure_link \"\$1\" \"\$2\" \"\$3\"
  " _ "$1" "$2" "${3:-hypr}" 2>&1
}

LINK="$TMP/home/.config/hypr/hyprsimple"
reset_home() { rm -rf "${TMP:?}/home"; mkdir -p "$TMP/home/.config"; }

# --- absent ------------------------------------------------------------------

reset_home
out=$(run_link "$TARGET" "$LINK")
check "a missing link is created" \
  "$([[ -L $LINK ]] && echo yes || echo no)" "yes"
check "pointing where it should" "$(readlink "$LINK")" "$TARGET"
check "and it resolves, so the defaults are actually reachable" \
  "$([[ -e $LINK/hyprlock.conf ]] && echo yes || echo no)" "yes"
check "and it says what it did" "$(printf '%s\n' "$out" | grep -c '^Relinked:')" "1"

# --- already correct ---------------------------------------------------------

out=$(run_link "$TARGET" "$LINK")
check "an intact link is left alone" "$(readlink "$LINK")" "$TARGET"
check "and says nothing, an ordinary update having nothing to report" \
  "$(printf '%s\n' "$out" | grep -c .)" "0"

# --- dangling, the case the rofi migration was written for -------------------

reset_home
mkdir -p "$(dirname "$LINK")"
ln -sfn "$TMP/gone/default/hypr" "$LINK"
check "the fixture really is dangling, or this proves nothing" \
  "$([[ -e $LINK ]] && echo resolves || echo dangling)" "dangling"
out=$(run_link "$TARGET" "$LINK")
check "a dangling link is repaired" "$(readlink "$LINK")" "$TARGET"
check "and resolves afterwards" \
  "$([[ -e $LINK/hyprlock.conf ]] && echo yes || echo no)" "yes"

# --- pointing at an old install path ------------------------------------------

reset_home
mkdir -p "$(dirname "$LINK")" "$TMP/oldinstall/default/hypr"
ln -sfn "$TMP/oldinstall/default/hypr" "$LINK"
check "a link to somewhere that exists but is not the install still resolves" \
  "$([[ -e $LINK ]] && echo resolves || echo dangling)" "resolves"
run_link "$TARGET" "$LINK" >/dev/null
check "and is still repointed at the install" "$(readlink "$LINK")" "$TARGET"

# --- a real directory in the way ----------------------------------------------
#
# `ln -sfn` onto an existing directory writes the link inside it, which is the
# accident install.sh once shipped as ~/.config/rofi/launcher/launcher. Nothing
# is replaced here, because whatever is there is somebody's.

reset_home
mkdir -p "$LINK"
: >"$LINK/mine.conf"
out=$(run_link "$TARGET" "$LINK")
check "a real directory is not replaced" \
  "$([[ -L $LINK ]] && echo link || echo directory)" "directory"
check "and what is in it is untouched" \
  "$([[ -f $LINK/mine.conf ]] && echo yes || echo no)" "yes"
# The link ln -sfn would leave inside the directory is named after the target,
# not after the link, so that is what this looks for. Checking for the link's
# own name found nothing whether the bug was present or not, which sabotage
# showed by leaving this green while the guard was deleted.
check "and no link is written inside it, which is what ln -sfn would do" \
  "$([[ -e "$LINK/$(basename "$TARGET")" ]] && echo nested || echo none)" "none"
check "and the user is told their defaults are not arriving" \
  "$(printf '%s\n' "$out" | grep -c 'not reaching it')" "1"

# --- a real file in the way ---------------------------------------------------

reset_home
mkdir -p "$(dirname "$LINK")"
printf 'mine\n' >"$LINK"
out=$(run_link "$TARGET" "$LINK")
check "a real file is not replaced either" "$(cat "$LINK")" "mine"
check "and is reported the same way" \
  "$(printf '%s\n' "$out" | grep -c 'not reaching it')" "1"

# --- the updater asks for all three -------------------------------------------

calls=$(grep -c '^ensure_link ' "$UPDATE")
check "the updater re-asserts three links" "$calls" "3"
for want in "default/hypr" "default/rofi" "default/dunst/10-hyprsimple.conf"; do
  check "including $want" \
    "$(grep -c "ensure_link .*$want" "$UPDATE")" "1"
done

# The same three install.sh creates, so the two cannot drift apart.
for want in "default/hypr\"" "default/rofi\"" "default/dunst/10-hyprsimple.conf\""; do
  check "and install.sh links $want too" \
    "$(grep -c "ln -sfn .*$want" "$REPO/install.sh")" "1"
done

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
