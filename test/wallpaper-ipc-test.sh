#!/bin/bash
# Checks that a wallpaper is shown by asking hyprpaper over its ipc, and that
# hyprpaper is restarted only when it does not answer.
#
# A restart was the only way it was done, and hyprpaper takes about two seconds
# to stop: measured on one machine, 1.9s of a 2.2s theme switch.
#
# hyprctl and systemctl are stand-ins that record what they were asked. Nothing
# here reaches the real hyprpaper or changes a wallpaper.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
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
# hyprctl answers the way hyprpaper does: nothing when it took the request, a
# line of text when it did not, and a failure when hyprpaper is not running.
cat >"$STUB/hyprctl" <<'STUBEOF'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$CALLS"
case "${HYPRPAPER:-ok}" in
ok) exit 0 ;;
refuses) echo "error: invalid hyprpaper request"; exit 0 ;;
down) echo "Couldn't connect to hyprpaper" >&2; exit 1 ;;
esac
STUBEOF
cat >"$STUB/systemctl" <<'STUBEOF'
#!/bin/bash
printf 'systemctl %s\n' "$*" >>"$CALLS"
STUBEOF
chmod +x "$STUB/hyprctl" "$STUB/systemctl"
for tool in hyprctl systemctl; do
  check "the real $tool is unreachable from here" "$(PATH="$STUB" command -v "$tool")" "$STUB/$tool"
done

show() {
  : >"$TMP/calls"
  CALLS="$TMP/calls" HYPRPAPER="$1" PATH="$STUB" "$BASH_BIN" -c \
    'source "$1"; show_wallpaper "$2"' _ "$BIN/hypr-helpers.sh" "$2"
}
restarts() { grep -c '^systemctl --user restart hyprpaper.service$' "$TMP/calls"; }

show ok "/themes/nord/backgrounds/a wall.webp"
check "the wallpaper is set over ipc, with its path whole" \
  "$(cat "$TMP/calls")" "hyprctl hyprpaper wallpaper ,/themes/nord/backgrounds/a wall.webp,cover"
check "and hyprpaper is not restarted" "$(restarts)" "0"

show ok "/themes/nord/backgrounds"
check "a folder to cycle through is set the same way" \
  "$(cat "$TMP/calls")" "hyprctl hyprpaper wallpaper ,/themes/nord/backgrounds,cover"

show refuses "/themes/nord/backgrounds/a.webp"
check "a request hyprpaper refuses falls back to a restart" "$(restarts)" "1"

show down "/themes/nord/backgrounds/a.webp"
check "and so does a hyprpaper that is not running" "$(restarts)" "1"

# ---- the two scripts that change the wallpaper use it ---------------------------

code() { sed 's/^[[:space:]]*#.*//' "$1"; }
check "a theme switch shows the wallpaper through it" \
  "$(code "$BIN/theme-switcher.sh" | grep -c 'show_wallpaper "\$SHOW"')" "1"
check "and no longer restarts hyprpaper itself" \
  "$(code "$BIN/theme-switcher.sh" | grep -c 'restart hyprpaper')" "0"
check "picking a wallpaper shows the image that was picked" \
  "$(code "$BIN/wallpaper-switcher.sh" | grep -c 'show_wallpaper "\$SELECTED"')" "1"
check "and no longer restarts hyprpaper itself" \
  "$(code "$BIN/wallpaper-switcher.sh" | grep -c 'restart hyprpaper')" "0"
# The cache file keeps its name when its content changes, so hyprpaper asked to
# show it again would have no reason to read it again.
check "neither asks hyprpaper to show the cache file" \
  "$(code "$BIN/theme-switcher.sh" "$BIN/wallpaper-switcher.sh" | grep -c 'show_wallpaper .*current_wallpaper')" "0"
check "hyprpaper.conf is still written, for the next login" \
  "$(code "$BIN/theme-switcher.sh" | grep -c 'write_hyprpaper_conf')" "2"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
