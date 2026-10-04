#!/bin/bash
# Checks the migration that carries rosepine's new wallpaper to an existing
# install, and that the updater waits for a restarted bar before it ends.
#
# Every home is a directory of this suite's own. theme-switcher.sh is a
# stand-in that records how it was called, so no theme is applied here.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
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
MIGRATION="$(grep -l '^echo "Replace the rosepine wallpaper"' "$REPO"/migrations/*.sh | head -1)"
check "the migration was found" "$([[ -n $MIGRATION ]] && echo found || echo missing)" "found"

NEW="$REPO/.config/hypr/themes/rosepine/backgrounds/0-rosepine.jpg"
check "rosepine ships the new wallpaper" "$([[ -f $NEW ]] && echo yes || echo no)" "yes"
check "and no longer the old one" \
  "$([[ -e $REPO/.config/hypr/themes/rosepine/backgrounds/0-with-you.jpg ]] && echo yes || echo no)" "no"

# The old picture is no longer anywhere in the tree, and a suite cannot read it
# out of git history, which CI's shallow checkout does not have. So the logic is
# run against a stand-in for it: a copy of the migration whose checksum is the
# stand-in's. The real checksum is only checked for its shape.
check "the migration removes the old picture by a sha256" \
  "$(grep -cE '^OLD_SHA="[0-9a-f]{64}"$' "$MIGRATION")" "1"
OLD_BYTES="$TMP/old.jpg"
printf 'the picture hyprsimple used to ship\n' >"$OLD_BYTES"
RUN="$TMP/migration.sh"
sed "s/^OLD_SHA=.*/OLD_SHA=\"$(sha256sum "$OLD_BYTES" | cut -d' ' -f1)\"/" "$MIGRATION" >"$RUN"
have_old=yes

home() {
  local h="$TMP/home-$1" active="$2"
  mkdir -p "$h/.config/hypr/themes/rosepine/backgrounds" "$h/.config/hypr/themes/nord/generated" \
    "$h/.config/hypr/themes/rosepine/generated" "$h/.local/bin"
  ln -s "$h/.config/hypr/themes/$active/generated/hyprland-colors.lua" "$h/.config/hypr/theme-active.lua"
  printf '#!/bin/bash\nprintf "%%s|%%s\\n" "$*" "${THEME_SWITCHER_NO_RELOAD:-}" >>"$SWITCHES"\n' \
    >"$h/.local/bin/theme-switcher.sh"
  chmod +x "$h/.local/bin/theme-switcher.sh"
  printf '%s' "$h"
}
migrate() {
  : >"$TMP/switches"
  HOME="$1" HYPRSIMPLE_PATH="$REPO" SWITCHES="$TMP/switches" HYPRLAND_INSTANCE_SIGNATURE="${SESSION:-}" \
    PATH="/usr/bin:/bin" "$BASH_BIN" "$RUN" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}
exists() { [[ -e $1 ]] && echo present || echo gone; }

if [[ $have_old == yes ]]; then
  h=$(home active rosepine); bg="$h/.config/hypr/themes/rosepine/backgrounds"
  cp "$OLD_BYTES" "$bg/0-with-you.jpg"
  SESSION=sig migrate "$h"
  check "the new wallpaper is copied in" "$(cmp -s "$NEW" "$bg/0-rosepine.jpg" && echo same || echo differs)" "same"
  check "the old one, as shipped, is removed" "$(exists "$bg/0-with-you.jpg")" "gone"
  check "rosepine in use is applied again, so the new one shows" "$(cat "$TMP/switches")" "rosepine|"
  check "and it succeeds" "$(cat "$TMP/rc")" "0"

  migrate "$h"
  check "run again it does nothing" "$(grep -c 'Nothing to do' "$TMP/out")" "1"
  check "and applies no theme" "$(wc -c <"$TMP/switches" | tr -d ' ')" "0"

  h=$(home tty rosepine); cp "$OLD_BYTES" "$h/.config/hypr/themes/rosepine/backgrounds/0-with-you.jpg"
  SESSION="" migrate "$h"
  check "with no session it is applied without reloading" "$(cat "$TMP/switches")" "rosepine|1"

  h=$(home other nord); bg="$h/.config/hypr/themes/rosepine/backgrounds"
  cp "$OLD_BYTES" "$bg/0-with-you.jpg"
  SESSION=sig migrate "$h"
  check "with another theme in use the files are still put right" \
    "$(exists "$bg/0-rosepine.jpg")$(exists "$bg/0-with-you.jpg")" "presentgone"
  check "and no theme is applied" "$(wc -c <"$TMP/switches" | tr -d ' ')" "0"
fi

# A picture of the user's own under the old name is not the shipped one.
h=$(home mine rosepine); bg="$h/.config/hypr/themes/rosepine/backgrounds"
printf 'my own picture\n' >"$bg/0-with-you.jpg"
SESSION=sig migrate "$h"
check "a picture of your own under the old name is left" "$(cat "$bg/0-with-you.jpg")" "my own picture"
check "and said to be" "$(grep -c 'is left where it is' "$TMP/out")" "1"
check "while the new wallpaper still arrives" "$(exists "$bg/0-rosepine.jpg")" "present"

# A home without the theme.
mkdir -p "$TMP/home-none"
migrate "$TMP/home-none"
check "a home without rosepine exits 0" "$(cat "$TMP/rc")" "0"
check "and creates nothing" "$(find "$TMP/home-none" -mindepth 1 | wc -l | tr -d ' ')" "0"

# ---- the updater waits for the bar it restarted ---------------------------------
#
# The bar shows the notifications, and one sent before a restarted bar is up
# has nowhere to go. A shell that announces a long command finishing sent one
# the moment the update ended, and printed an error under "up to date".
UPDATE="$REPO/.local/bin/hyprsimple-update.sh"
code=$(sed 's/^[[:space:]]*#.*//' "$UPDATE")
restart_line=$(grep -n 'hyprsimple-restart-bar.sh" --if-running' <<<"$code" | cut -d: -f1)
wait_line=$(grep -n 'busctl --user status org.freedesktop.Notifications' <<<"$code" | cut -d: -f1)
check "the updater waits for the bar to take notifications" "$([[ -n $wait_line ]] && echo yes || echo no)" "yes"
check "after restarting it" "$((wait_line > restart_line))" "1"
check "and only for a bounded time" "$(grep -c 'for _ in {1..50}; do' <<<"$code")" "1"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
