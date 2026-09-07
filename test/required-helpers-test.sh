#!/bin/bash
# Checks that a missing helper stops the script rather than being announced as
# success.
#
# theme-switcher.sh, wallpaper-switcher.sh and live-wallpaper-toggle.sh source
# helpers out of ~/.local/bin. `source` on a file that is not there prints one
# line and returns non-zero, and none of these set -e, so each carried on with
# the helper's functions undefined. bash reports every missing function on
# stderr and keeps going, so the script reached its end and said it had worked.
#
# Measured before the fix, with the helper removed, which is the state of any
# install whose ~/.local/bin predates it:
#
#   theme-switcher.sh deep-sea      exit 0, "Theme 'deep-sea' applied!", and
#                                   none of the eight generated files delivered
#   wallpaper-switcher.sh next      exit 0, "Wallpaper 2-deep-sea.jpg", and
#                                   hyprpaper.conf never written at all
#
# Nothing here touches the real ~/.config, and no compositor is contacted:
# hyprctl, systemctl, busctl, gsettings and notify-send are all stubs.

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
for helper in pass fail check; do
  declare -F "$helper" >/dev/null || { printf 'not ok - helper %s missing\n' "$helper" >&2; exit 1; }
done

STUB="$TMP/bin"; mkdir -p "$STUB"
for c in hyprctl systemctl busctl gsettings brightnessctl; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$c"
done
# pkill and pgrep are stubbed too. theme-switcher.sh ends by restarting waybar
# and dunst through --if-running, and an unstubbed pkill here would reach the
# maintainer's own session.
printf '#!/bin/bash\nexit 1\n' >"$STUB/pgrep"
printf '#!/bin/bash\nexit 0\n' >"$STUB/pkill"
# rofi above all. These scripts open a picker when given no argument, and
# /usr/bin is on the PATH below, so the real rofi was reachable. It opened a
# window on the maintainer's screen during a sabotage run, complaining about a
# theme inside the fixture. theme-picker-test.sh has warned about exactly this
# since it was written; this suite did not carry the stub over.
#
# It answers with nothing, so a picker that is reached selects nothing and the
# caller exits rather than waiting for input.
printf '#!/bin/bash\nexit 1\n' >"$STUB/rofi"
cat >"$STUB/notify-send" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$NOTIFY_LOG"
STUBEOF
chmod +x "$STUB"/*

NLOG="$TMP/notifications"

# A fixture home holding a theme with colours to render, so the scripts have
# real work to do rather than exiting early for a reason of their own.
build_home() {
  local home="$1"
  rm -rf "${home:?}"
  mkdir -p "$home/.local/bin" "$home/.cache" "$home/.config/waybar" \
    "$home/.config/rofi/launcher" "$home/.config/rofi/powermenu" \
    "$home/.config/hypr/themes/demo/backgrounds" \
    "$home/.config/hypr/themes/templates"
  cp "$BIN"/*.sh "$home/.local/bin/"
  printf 'x\n' >"$home/.config/rofi/launcher/style.rasi"
  printf 'x\n' >"$home/.config/rofi/powermenu/style.rasi"
  cp "$REPO/.config/hypr/themes/templates"/*.tpl "$home/.config/hypr/themes/templates/"
  cp "$REPO/.config/hypr/themes/deep-sea/colors.toml" \
    "$home/.config/hypr/themes/demo/colors.toml"
  # Two wallpapers, so wallpaper-switcher.sh has somewhere to cycle to. Real
  # files rather than empty ones, because it copies them.
  printf 'not-really-an-image-1\n' >"$home/.config/hypr/themes/demo/backgrounds/1-one.jpg"
  printf 'not-really-an-image-2\n' >"$home/.config/hypr/themes/demo/backgrounds/2-two.jpg"
  printf '%s\n' "$home/.config/hypr/themes/demo/backgrounds/1-one.jpg" \
    >"$home/.cache/current_wallpaper_path"
}

run_in() {
  local home="$1" script="$2"; shift 2
  : >"$NLOG"
  # HYPRSIMPLE_PATH, because theme-apply-templates.sh reads its templates out
  # of the install rather than the home. Without it the render produced nothing
  # and the delivery had nothing to deliver, which looked like the bug.
  #
  # THEME_SWITCHER_NO_RELOAD is deliberately not set: it suppresses the very
  # notification these checks read. The reloads it would skip are all stubbed.
  NOTIFY_LOG="$NLOG" HYPRSIMPLE_PATH="$REPO" HOME="$home" \
    PATH="$STUB:/usr/bin:/bin" \
    bash "$home/.local/bin/$script" "$@" >/dev/null 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

HOME_FIXTURE="$TMP/home"

# ---- the fixture works when nothing is missing -----------------------------
#
# Asserted first. Every check below is about a script stopping, and a fixture
# where the script never got anywhere would satisfy all of them for the wrong
# reason.

build_home "$HOME_FIXTURE"
run_in "$HOME_FIXTURE" theme-switcher.sh demo
check "with every helper present, a theme switch succeeds" "$(cat "$TMP/rc")" "0"
check "and says so" "$(grep -c "Theme 'demo' applied" "$NLOG")" "1"
check "and the delivery really ran, which is what a missing helper skips" \
  "$([[ -e $HOME_FIXTURE/.config/waybar/theme-active.css ]] && echo delivered || echo missing)" \
  "delivered"

build_home "$HOME_FIXTURE"
run_in "$HOME_FIXTURE" wallpaper-switcher.sh next
check "and a wallpaper switch succeeds" "$(cat "$TMP/rc")" "0"
check "and writes the config hyprpaper reads" \
  "$([[ -f $HOME_FIXTURE/.config/hypr/hyprpaper.conf ]] && echo written || echo missing)" \
  "written"

# ---- each helper removed in turn -------------------------------------------
#
# The pairs are read out of the scripts rather than listed here, so a caller
# that starts requiring something new is covered without this file being
# touched, and one that stops requiring anything at all is caught by the count.

mapfile -t requirements < <(
  for script in "$BIN"/*.sh; do
    sed 's/#.*//' "$script" |
      grep -oE '^require_helper .*' |
      sed "s|^require_helper ||; s|^|$(basename "$script") |"
  done
)
if (( ${#requirements[@]} < 3 )); then
  fail "found ${#requirements[@]} scripts calling require_helper, which is fewer than there are"
else
  pass "found ${#requirements[@]} scripts calling require_helper"
fi

for line in "${requirements[@]}"; do
  script="${line%% *}"
  for needed in ${line#* }; do
    build_home "$HOME_FIXTURE"
    rm -f "$HOME_FIXTURE/.local/bin/$needed"
    run_in "$HOME_FIXTURE" "$script"
    check "$script stops when $needed is missing" \
      "$([[ $(cat "$TMP/rc") != "0" ]] && echo stopped || echo continued)" "stopped"
    check "and names it rather than claiming success" \
      "$(grep -c "Missing helper: .*$needed" "$NLOG")" "1"
    check "and announces nothing else" \
      "$(grep -cv 'Missing helper' "$NLOG")" "0"
  done
done

# ---- the guard on the guard ------------------------------------------------
#
# require_helper is itself sourced, so its own absence cannot be caught by it.
# Each caller carries that one check inline.

for script in theme-switcher.sh wallpaper-switcher.sh live-wallpaper-toggle.sh; do
  build_home "$HOME_FIXTURE"
  rm -f "$HOME_FIXTURE/.local/bin/hyprsimple-require.sh"
  run_in "$HOME_FIXTURE" "$script"
  check "$script stops when hyprsimple-require.sh itself is missing" \
    "$([[ $(cat "$TMP/rc") != "0" ]] && echo stopped || echo continued)" "stopped"
  check "and says which file it wanted" \
    "$(grep -c 'hyprsimple-require.sh' "$NLOG")" "1"
done

# ---- nothing is left sourcing a helper without the check -------------------
#
# Comments stripped: hyprsimple-require.sh documents the old shape in one.

blind=()
while IFS= read -r hit; do
  [[ -n $hit ]] && blind+=("$hit")
done < <(
  for script in "$BIN"/*.sh; do
    sed 's/#.*//' "$script" |
      grep -qE '^source "\$HOME/\.local/bin/[a-z-]+\.sh"$' &&
      basename "$script"
  done
)
blind_str=""; (( ${#blind[@]} > 0 )) && blind_str="$(printf '%s ' "${blind[@]}")"
check "no script sources a helper without a check on it" "$blind_str" ""

# And the one line that has to source without require_helper carries its own
# check, on every caller.
guarded=0
for script in theme-switcher.sh wallpaper-switcher.sh live-wallpaper-toggle.sh; do
  sed 's/#.*//' "$BIN/$script" |
    grep -q 'source "$HOME/.local/bin/hyprsimple-require.sh" 2>/dev/null ||' &&
    guarded=$((guarded + 1))
done
check "and every caller guards the line that loads the checker itself" "$guarded" "3"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
