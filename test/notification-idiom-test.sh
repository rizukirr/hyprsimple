#!/bin/bash
# hyprsimple sent notifications two ways, notify-send and dunstify, with no rule
# saying which. This suite pins the single idiom, and the one behaviour the
# substitution could have broken silently: volume and brightness replace their
# own previous notification by id rather than stacking.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

check "no script calls dunstify" \
  "$(grep -rlE '(^|[^[:alnum:]_-])dunstify' "$REPO/.local/bin/" | wc -l | tr -d ' ')" "0"

# dunstctl is a different tool with no notify-send equivalent, so the check
# above must not become a blanket ban on everything dunst ships.
check "notification-dismiss.sh still uses dunstctl" \
  "$(grep -c 'dunstctl' "$REPO/.local/bin/notification-dismiss.sh")" "1"

# The replace-by-id sites, named so a future edit that drops -r shows up here
# rather than only on someone's screen.
check "volume-notify still replaces by id" \
  "$(grep -c -- '-r "\?\$NOTIFY_ID' "$REPO/.local/bin/volume-notify.sh")" "2"
check "brightness-notify still replaces by id" \
  "$(grep -c -- '-r "\?\$NOTIFY_ID' "$REPO/.local/bin/brightness-notify.sh")" "1"

# The behaviour itself, against the running daemon. Skipped loudly where dunst
# is not running, which includes CI. A check that silently degrades into a
# no-op on the runner reads as coverage while proving nothing.
if command -v dunstctl >/dev/null 2>&1 && pgrep -x dunst >/dev/null 2>&1; then
  dunstctl close-all
  notify-send -u low -t 3000 -r 4242 "probe" "first"
  notify-send -u low -t 3000 -r 4242 "probe" "second"
  check "two notify-send with one id display as one notification" \
    "$(dunstctl count displayed)" "1"

  # Discrimination: the check above is worthless unless the same pair without
  # -r would actually display two.
  dunstctl close-all
  notify-send -u low -t 3000 "probe" "first"
  notify-send -u low -t 3000 "probe" "second"
  check "the same pair without an id displays as two" \
    "$(dunstctl count displayed)" "2"
  dunstctl close-all
else
  printf 'skip - dunst not running, replacement behaviour not exercised\n'
fi

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
