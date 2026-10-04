#!/bin/bash
# The theme and wallpaper pickers are panels of the bar. This checks the three
# pieces on the script side: that the two switchers open the right panel when
# asked to pick, that they still apply when given a choice, and that the
# thumbnail script turns a picker feed into one the bar can show.
#
# qs, magick and everything a switcher would reload are stand-ins, and HOME is
# a folder of this suite's own.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
BAR_QML="$REPO/default/quickshell/bar/Bar.qml"
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
# qs records what it was asked. The real one would open a panel on the screen
# of whoever is running this.
cat >"$STUB/qs" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$QS_LOG"
STUBEOF
for tool in notify-send hyprctl systemctl gsettings pkill busctl; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$tool"
done
printf '#!/bin/bash\nexit 1\n' >"$STUB/pgrep"
chmod +x "$STUB"/*

H="$TMP/home"
mkdir -p "$H/.local/bin" "$H/.cache" "$H/.config/hypr/themes/demo/backgrounds"
cp "$BIN"/*.sh "$H/.local/bin/"
chmod +x "$H/.local/bin"/*.sh
printf 'one\n' >"$H/.config/hypr/themes/demo/backgrounds/1-one.jpg"
printf 'two\n' >"$H/.config/hypr/themes/demo/backgrounds/2-two.jpg"
printf '%s\n' "$H/.config/hypr/themes/demo/backgrounds/1-one.jpg" >"$H/.cache/current_wallpaper_path"

run() {
  : >"$TMP/qs-log"
  QS_LOG="$TMP/qs-log" HOME="$H" \
    XDG_CONFIG_HOME="$H/.config" THEME_SWITCHER_NO_RELOAD=1 \
    PATH="$STUB:/usr/bin:/bin" bash "$H/.local/bin/$1" "${@:2}" >/dev/null 2>&1
}
BAR_PATH="$H/.local/share/hyprsimple/default/quickshell"

# ---- the switchers open the bar's pickers ----------------------------------

run theme-switcher.sh
check "theme-switcher.sh with no theme opens the bar's theme picker" \
  "$(cat "$TMP/qs-log")" "-p $BAR_PATH ipc call bar toggle themes"

run wallpaper-switcher.sh pick
check "wallpaper-switcher.sh pick opens the bar's wallpaper picker" \
  "$(cat "$TMP/qs-log")" "-p $BAR_PATH ipc call bar toggle wallpapers"

# The names the scripts open have to be names the bar has a panel for.
for panel in themes wallpapers; do
  check "the bar has a panel named $panel" "$(grep -c "name: \"$panel\"" "$BAR_QML")" "1"
done

# And what the panels run to apply a choice has to be what the scripts accept.
check "the theme picker applies through theme-switcher.sh" \
  "$(grep -c 'applyCommand: \[Quickshell.env("HOME") + "/.local/bin/theme-switcher.sh"\]' "$BAR_QML")" "1"
check "and the wallpaper picker through wallpaper-switcher.sh apply" \
  "$(grep -c 'applyCommand: \[Quickshell.env("HOME") + "/.local/bin/wallpaper-switcher.sh", "apply"\]' "$BAR_QML")" "1"

# ---- applying still works, and opens nothing -------------------------------

run wallpaper-switcher.sh apply "$H/.config/hypr/themes/demo/backgrounds/2-two.jpg"
check "wallpaper-switcher.sh apply sets the wallpaper it was given" \
  "$(cat "$H/.cache/current_wallpaper_path")" "$H/.config/hypr/themes/demo/backgrounds/2-two.jpg"
check "without opening a picker" "$(wc -l <"$TMP/qs-log" | tr -d ' ')" "0"

run theme-switcher.sh demo
check "theme-switcher.sh with a theme opens no picker either" \
  "$(grep -c 'toggle themes' "$TMP/qs-log")" "0"

# ---- the thumbnail script --------------------------------------------------

# magick writes a marker naming its source as the thumbnail, and counts its runs.
cat >"$STUB/magick" <<'STUBEOF'
#!/bin/bash
printf 'made\n' >>"$MAGICK_CALLS"
out="${*: -1}"
printf 'thumbnail of %s\n' "$1" >"$out"
STUBEOF
chmod +x "$STUB/magick"

IMG="$TMP/images"; mkdir -p "$IMG"
printf 'a\n' >"$IMG/a.webp"
printf 'b\n' >"$IMG/b with space.jpg"
feed() {
  printf 'key-a\tlabel a\t%s\n' "$IMG/a.webp"
  printf 'key-b\t<span background='"'"'#112233'"'"'>  </span>  label b\t%s\n' "$IMG/b with space.jpg"
  printf 'key-c\tno picture\t\n'
  printf 'key-d\tgone\t%s\n' "$IMG/missing.png"
}
thumbs() {
  : >"$TMP/magick-calls"
  feed | MAGICK_CALLS="$TMP/magick-calls" XDG_CACHE_HOME="$TMP/cache" \
    PATH="$STUB:/usr/bin:/bin" bash "$BIN/hyprsimple-thumbnails.sh" >"$TMP/out" 2>/dev/null
}

thumbs
check "every row comes back out" "$(wc -l <"$TMP/out" | tr -d ' ')" "4"
check "with its key and label untouched, markup included" \
  "$(cut -f1,2 "$TMP/out")" "$(feed | cut -f1,2)"
a_thumb=$(sed -n 1p "$TMP/out" | cut -f3)
check "an image is swapped for a thumbnail in the cache" \
  "$([[ $a_thumb == "$TMP/cache/hyprsimple/picker-thumbnails/"*.jpg ]] && echo cached || echo "$a_thumb")" "cached"
check "which was made from that image" "$(cat "$a_thumb")" "thumbnail of $IMG/a.webp"
check "an image with a space in its name gets one too" \
  "$(cat "$(sed -n 2p "$TMP/out" | cut -f3)")" "thumbnail of $IMG/b with space.jpg"
check "a row with no image keeps an empty image column" "$(sed -n 3p "$TMP/out" | cut -f3)" ""
check "and so does one whose image is missing" "$(sed -n 4p "$TMP/out" | cut -f3)" ""
check "one thumbnail was made per image that exists" "$(wc -l <"$TMP/magick-calls" | tr -d ' ')" "2"
check "and no half-written file is left in the cache" \
  "$(find "$TMP/cache" -name '*.tmp.jpg' | wc -l | tr -d ' ')" "0"

thumbs
check "a second run reuses them" "$(wc -l <"$TMP/magick-calls" | tr -d ' ')" "0"

# A changed image is thumbnailed again. The thumbnail is made older than the
# image rather than the image touched, so this does not depend on the clock.
touch -d '2001-01-01' "$a_thumb"
thumbs
check "an image newer than its thumbnail is thumbnailed again" "$(wc -l <"$TMP/magick-calls" | tr -d ' ')" "1"

# Without ImageMagick the picker should still show something.
# A PATH holding only the tools the script needs, so that neither magick nor
# convert is found even on a machine that has them.
BARE="$TMP/bare"; mkdir -p "$BARE"
for tool in mkdir md5sum cut readlink mv rm; do
  ln -s "$(command -v "$tool")" "$BARE/$tool"
done
rm -rf "$TMP/cache"
feed | XDG_CACHE_HOME="$TMP/cache" PATH="$BARE" "$BASH" "$BIN/hyprsimple-thumbnails.sh" >"$TMP/out" 2>/dev/null
check "with nothing to make thumbnails, a row falls back to the image itself" \
  "$(sed -n 1p "$TMP/out" | cut -f3)" "$IMG/a.webp"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
