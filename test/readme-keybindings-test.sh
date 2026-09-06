#!/bin/bash
# The README's keybinding tables are what someone reads before pressing a key,
# and nothing checked them against the keys hyprsimple actually binds.
#
# One had already drifted. SUPER + CTRL + Print was documented as
#
#   | `SUPER + CTRL + Print` | Screenshot region to clipboard |
#
# and it is bound to `screenshot.sh clipboard`, which runs
#
#   hyprshot -m output --clipboard-only --silent
#
# `-m output` is the whole monitor. So the key documented as taking a region
# silently copied the entire screen, which is the wrong surprise to get in the
# middle of a meeting.
#
# This compares the two sets of keys in both directions. It does not try to
# match the prose, which is a judgement rather than a fact, so a description
# can still go stale. What it catches is a key documented and not bound, or
# bound and not documented, which is the drift that made the above possible.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
README="$REPO/README.md"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- what is bound -----------------------------------------------------------
#
# Comments stripped first. applications.lua carries two commented examples,
# SUPER + O and SUPER + S, and counting them would demand README rows for keys
# nobody has bound. The stripper is anchored to the start of the line so that
# `uwsm app -- waybar` keeps its dashes, which is the mistake the lua stripper
# in another suite made once.
lua_files=(
  "$REPO/default/hypr/bindings.lua"
  "$REPO/default/hypr/bindings"/*.lua
  "$REPO/.config/hypr/bindings"/*.lua
)

# Flattened to one line before matching, because several binds put the key on
# the line after hl.bind( and a line-at-a-time grep sees none of them. That
# missed SUPER + SHIFT + S, which is bound, and reported it as documented but
# unbound.
bound_all=$(
  for f in "${lua_files[@]}"; do
    [[ -f $f ]] || continue
    sed 's/^[[:space:]]*--.*//' "$f"
  done | tr '\n' ' ' | grep -oE 'hl\.bind\([[:space:]]*"[^"]*"' |
    sed 's/hl\.bind([[:space:]]*"//; s/"$//' | LC_ALL=C sort -u
)

# workspaces.lua builds ten pairs of keys in a loop, so what a literal match
# sees there is the prefix "SUPER + " with nothing after it. Those are dropped
# here and the loop is checked on its own below, rather than pretending a
# prefix is a key.
bound=$(printf '%s\n' "$bound_all" | grep -vE '\+ $' | grep -v '^$')
bound_count=$(printf '%s\n' "$bound" | grep -c .)

if (( bound_count < 40 )); then
  fail "found only $bound_count bindings, so the extractor is not reading the files"
else
  pass "read $bound_count bindings from the config"
fi

# The stripper has to remove the commented examples and nothing else.
check "a commented-out example is not counted as a binding" \
  "$(printf '%s\n' "$bound" | grep -cx 'SUPER + O')" "0"
check "and a real binding beside it still is" \
  "$(printf '%s\n' "$bound" | grep -cx 'SUPER + A')" "1"

# --- what the README documents -----------------------------------------------
#
# Only the rows between the Keybindings heading and the Scripts one. The
# Scripts tables use the same row shape for filenames, and reading those as
# keys is how a check like this quietly stops meaning anything.
start=$(grep -n '^## Keybindings' "$README" | head -1 | cut -d: -f1)
end=$(grep -n '^## Scripts' "$README" | head -1 | cut -d: -f1)
if [[ -z $start || -z $end ]] || (( end <= start )); then
  fail "could not find the Keybindings section in README.md"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi

documented=$(
  sed -n "${start},${end}p" "$README" |
    grep -oE '^\| `[^`]+`' | sed 's/^| `//; s/`$//' | LC_ALL=C sort -u
)
documented_count=$(printf '%s\n' "$documented" | grep -c .)
if (( documented_count < 30 )); then
  fail "found only $documented_count documented keys, so the section was not read"
else
  pass "read $documented_count keys from the README"
fi
check "and stopped before the Scripts tables, which look the same" \
  "$(printf '%s\n' "$documented" | grep -c '\.sh$')" "0"

# --- the shorthands the README uses on purpose -------------------------------
#
# One row standing for several keys is easier to read than ten rows, so these
# are expanded rather than treated as drift. Written out rather than pattern
# matched, so adding a shorthand is a deliberate act and a typo in one shows up
# as a missing key instead of being absorbed.
expand() {
  case "$1" in
    # The two workspace rows stand for keys workspaces.lua generates in a loop,
    # so there is no literal to match. They are dropped here and the loop is
    # checked directly.
    'SUPER + [1-9, 0]' | 'SUPER + SHIFT + [1-9, 0]') ;;
    'SUPER + H / J / K / L')   printf 'SUPER + %s\n' H J K L ;;
    'SUPER + SHIFT + Arrow')   printf 'SUPER + SHIFT + %s\n' UP DOWN LEFT RIGHT ;;
    'SUPER + CTRL + Arrow')    printf 'SUPER + CTRL + %s\n' UP DOWN LEFT RIGHT ;;
    'SUPER + LMB drag')        printf 'SUPER + mouse:272\n' ;;
    'SUPER + RMB drag')        printf 'SUPER + mouse:273\n' ;;
    'SUPER + Scroll')          printf 'SUPER + mouse_up\nSUPER + mouse_down\n' ;;
    'SUPER + /')               printf 'SUPER + slash\n' ;;
    'SUPER + ESC')             printf 'SUPER + ESCAPE\n' ;;
    'CTRL + ESC')              printf 'CTRL + ESCAPE\n' ;;
    'Volume Up / Down')        printf 'XF86AudioRaiseVolume\nXF86AudioLowerVolume\n' ;;
    'Mute')                    printf 'XF86AudioMute\n' ;;
    'Mic Mute')                printf 'XF86AudioMicMute\n' ;;
    'Play / Pause')            printf 'XF86AudioPlay\nXF86AudioPause\n' ;;
    'Next / Prev')             printf 'XF86AudioNext\nXF86AudioPrev\n' ;;
    'Brightness Up / Down')    printf 'XF86MonBrightnessUp\nXF86MonBrightnessDown\n' ;;
    'Kbd Brightness Up / Down') printf 'XF86KbdBrightnessUp\nXF86KbdBrightnessDown\n' ;;
    *)                         printf '%s\n' "$1" ;;
  esac
}

expanded=$(while IFS= read -r row; do [[ -n $row ]] && expand "$row"; done <<<"$documented" | LC_ALL=C sort -u)

# A shorthand that stops matching anything is drift too, so the expansion has
# to actually grow the list.
expanded_count=$(printf '%s\n' "$expanded" | grep -c .)
if (( expanded_count > documented_count )); then
  pass "the shorthand rows expand to $expanded_count keys"
else
  fail "expansion produced $expanded_count keys from $documented_count rows, so it is doing nothing"
fi

# --- the two sets have to agree ----------------------------------------------

# LC_ALL=C on comm as well as on the sorts. Without it comm collates by the
# runner's locale, decides the input it was just handed is unsorted, and says
# so on stderr while still producing an answer.
undocumented=$(LC_ALL=C comm -23 <(printf '%s\n' "$bound") <(printf '%s\n' "$expanded") | tr '\n' ' ')
check "every key hyprsimple binds is in the README" "$undocumented" ""

unbound=$(LC_ALL=C comm -13 <(printf '%s\n' "$bound") <(printf '%s\n' "$expanded") | tr '\n' ' ')
check "and every key the README documents is bound" "$unbound" ""

# --- the generated workspace keys --------------------------------------------
#
# Checked by shape rather than by key, since there is no literal to compare.

WS="$REPO/default/hypr/bindings/workspaces.lua"
# Flattened for the same reason as the extractor above: the shifted bind spans
# four lines, so a line-at-a-time grep reports it missing from a file that has
# it.
ws_flat=$(tr '\n' ' ' <"$WS")
check "workspaces are bound in a loop over all ten" \
  "$(grep -c 'for ws = 1, 10 do' "$WS")" "1"
check "which binds a plain key per workspace" \
  "$(printf '%s' "$ws_flat" | grep -c 'hl.bind("SUPER + " .. key')" "1"
check "and a shifted one to move a window there" \
  "$(printf '%s' "$ws_flat" | grep -oc 'hl.bind([[:space:]]*"SUPER + SHIFT + " .. key')" "1"
check "and the README documents both rows" \
  "$(printf '%s\n' "$documented" | grep -cE '^SUPER \+ (SHIFT \+ )?\[1-9, 0\]$')" "2"

# --- the row that was wrong --------------------------------------------------
#
# The key sets agreed while this was wrong, because both sides named the key.
# Only the description differed, and descriptions are not compared. So the one
# case that prompted the suite is pinned by name.
clip_mode=$(grep -A1 'hl.bind("SUPER + CTRL + Print"' "$REPO/default/hypr/bindings/screenshot.lua" |
  grep -oE 'screenshot\.sh [a-z]+' | awk '{print $2}')
check "SUPER + CTRL + Print runs the clipboard mode" "$clip_mode" "clipboard"
check "and that mode captures the whole output, not a region" \
  "$(sed -n '/^clipboard)/,/;;/p' "$REPO/.local/bin/screenshot.sh" | grep -c -- '-m output')" "1"
check "so the README says monitor rather than region" \
  "$(sed -n "${start},${end}p" "$README" | grep -c 'SUPER + CTRL + Print` | Screenshot current monitor to clipboard')" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
