#!/bin/bash
# Checks that one wallpaper is shown by asking hyprpaper over its ipc, that a
# folder of them is not, and that a restart does not wait for hyprpaper to stop.
#
# A restart was the only way it was done, and hyprpaper takes about two seconds
# to stop: measured on one machine, 1.9s of a 2.2s theme switch.
#
# A folder was sent over ipc once. hyprpaper answered as if it had taken it,
# then failed to load it as an image, and the screen had no wallpaper.
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
# What is on screen now, one "monitor: path" line each, as hyprpaper prints it.
if [[ $* == "hyprpaper listactive" && ${HYPRPAPER:-ok} == ok ]]; then
  [[ -n ${ACTIVE:-} ]] && printf 'eDP-1: %s\n' "$ACTIVE"
  exit 0
fi
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
# Stopped at once, then started, in that order.
fast_restart() { grep '^systemctl' "$TMP/calls" | paste -sd'|'; }
# reset-failed between them: systemd refuses to start a unit that failed five
# times in ten seconds, and a unit killed this way counts as failed. Without it
# a few theme switches in a row left hyprpaper down.
FAST="systemctl --user kill --signal=SIGKILL hyprpaper.service|systemctl --user reset-failed hyprpaper.service|systemctl --user restart hyprpaper.service"

# Real paths, since the helper tells an image from a folder by looking.
BG="$TMP/themes/nord/backgrounds"; mkdir -p "$BG"
: >"$BG/a wall.webp"; : >"$BG/b.webp"

show ok "$BG/a wall.webp"
check "one image is set over ipc, with its path whole" \
  "$(cat "$TMP/calls")" "hyprctl hyprpaper wallpaper ,$BG/a wall.webp,cover"
check "and hyprpaper is not restarted" "$(restarts)" "0"

show ok "$BG"
check "a folder is never sent over ipc, which takes it and then shows nothing" \
  "$(grep -c '^hyprctl' "$TMP/calls")" "0"
check "hyprpaper is started again on its config instead, without waiting for it to stop" \
  "$(fast_restart)" "$FAST"

show refuses "$BG/b.webp"
check "an image hyprpaper refuses falls back to the same restart" "$(fast_restart)" "$FAST"

show down "$BG/b.webp"
check "and so does a hyprpaper that is not running" "$(fast_restart)" "$FAST"

show ok "$BG/gone.webp"
check "an image that is not there is not sent either" "$(grep -c '^hyprctl' "$TMP/calls")" "0"

# ---- a folder holding one image is that image ------------------------------------
#
# Live wallpaper hands show_wallpaper the theme's folder, and that meant a
# restart on every theme switch. 37 of the 40 shipped themes have one image, so
# there was nothing to cycle through and the restart bought nothing. It is not
# the 0.01s it was once measured at either. On a hyprpaper that had been up for
# more than a few seconds:
#
#   systemctl restart, after the SIGKILL   1.836s, 1.846s
#   the same on one three seconds old      0.035s, 0.031s
#   one image over ipc                     0.015s
#
# So a theme switch waited almost two seconds for its wallpaper.
ONE="$TMP/themes/gruvbox/backgrounds"; mkdir -p "$ONE"
: >"$ONE/only one.JPG"
SOLO="$TMP/themes/dracula/backgrounds"; mkdir -p "$SOLO"
: >"$SOLO/0-dracula.webp"

show_while() {
  : >"$TMP/calls"
  CALLS="$TMP/calls" ACTIVE="$1" HYPRPAPER="${3:-ok}" PATH="$STUB" "$BASH_BIN" -c \
    'source "$1"; show_wallpaper "$2"' _ "$BIN/hypr-helpers.sh" "$2"
}

show_while "$SOLO/0-dracula.webp" "$ONE"
check "a folder of one image is set over ipc, as that image" \
  "$(grep -c "^hyprctl hyprpaper wallpaper ,$ONE/only one.JPG,cover$" "$TMP/calls")" "1"
check "and hyprpaper is not restarted" "$(restarts)" "0"

# hyprpaper cycling through the last theme's folder is still doing so after an
# ipc request, so that one has to be stopped.
show_while "$BG/b.webp" "$ONE"
check "unless hyprpaper is cycling through several now, which only a restart stops" \
  "$(fast_restart)" "$FAST"
check "and then nothing is sent over ipc" "$(grep -c '^hyprctl hyprpaper wallpaper' "$TMP/calls")" "0"

show_while "" "$ONE" down
check "a folder of one image still restarts a hyprpaper that is not running" "$(fast_restart)" "$FAST"

show_while "$SOLO/0-dracula.webp" "$BG"
check "a folder of several is still never sent over ipc" "$(grep -c '^hyprctl' "$TMP/calls")" "0"
check "and still restarts" "$(fast_restart)" "$FAST"

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

# ---- the bar can show a webp wallpaper ------------------------------------------
#
# A theme switch puts the wallpaper in its notification, and the bar that shows
# it is Qt, which reads webp only through qt6-imageformats.
webp=$(find "$REPO/.config/hypr/themes" -path '*/backgrounds/*' -name '*.webp' | wc -l | tr -d ' ')
if ((webp < 1)); then
  pass "no shipped wallpaper is webp, so the bar needs nothing more to show one"
else
  check "$webp shipped wallpapers are webp, and what lets the bar read them is installed" \
    "$(grep -cx 'qt6-imageformats' "$REPO/packages.txt")" "1"
fi

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
