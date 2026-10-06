#!/bin/bash
# Checks the rows the bar's theme and wallpaper pickers are fed. Never touches
# the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PICKER="$REPO/.local/bin/hyprsimple-theme-picker.sh"
WALLPAPER_PICKER="$REPO/.local/bin/hyprsimple-wallpaper-picker.sh"
WALLPAPER_SWITCHER="$REPO/.local/bin/wallpaper-switcher.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# Every fixture home goes through this before a run touches it. An empty path
# would make later rm/cp calls operate against the real $HOME, which is the
# environment this suite runs in.
must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'fixture: refusing to use path [%s], expected a path under %s\n' "${1:-}" "$TMP" >&2
    exit 2
  fi
}

# Same ImageMagick 6 and 7 shim the picker and the image optimizer carry.
if command -v magick >/dev/null 2>&1; then
  im_fixture() { magick "$@"; }
else
  im_fixture() { convert "$@"; }
fi
make_wallpaper() { im_fixture -size 400x300 xc:gray "$1"; }

# ---- a fixture with three themes emits three lines ------------------------

three_themes="$TMP/themes-three"
must_be_fixture "$three_themes"
mkdir -p "$three_themes/alpha/backgrounds" "$three_themes/beta/backgrounds" "$three_themes/gamma/backgrounds"
make_wallpaper "$three_themes/alpha/backgrounds/wall.jpg"
make_wallpaper "$three_themes/beta/backgrounds/wall.jpg"
make_wallpaper "$three_themes/gamma/backgrounds/wall.jpg"

three_cache="$TMP/cache-three"
out_three="$TMP/out-three"
THEMES_DIR="$three_themes" XDG_CACHE_HOME="$three_cache" bash "$PICKER" >"$out_three"

check "a fixture with three themes emits three lines" "$(wc -l <"$out_three")" "3"

# ---- swatches carry the theme's accent, and change when it changes --------

colortest_themes="$TMP/themes-color"
must_be_fixture "$colortest_themes"
mkdir -p "$colortest_themes/colortest"
cat >"$colortest_themes/colortest/colors.toml" <<'EOF'
accent = "#ff00ff"
color1 = "#111111"
color2 = "#222222"
color4 = "#444444"
EOF

color_cache="$TMP/cache-color"
line_before=$(THEMES_DIR="$colortest_themes" XDG_CACHE_HOME="$color_cache" bash "$PICKER")

check "a theme's accent shows up as a span in the emitted line" \
  "$(grep -c "background='#ff00ff'" <<<"$line_before")" "1"

sed -i "s/#ff00ff/#00ff00/" "$colortest_themes/colortest/colors.toml"
line_after=$(THEMES_DIR="$colortest_themes" XDG_CACHE_HOME="$color_cache" bash "$PICKER")

check "changing the accent changes the emitted span" \
  "$([[ $line_before != "$line_after" ]] && echo changed || echo unchanged)" "changed"
check "the new accent shows up after the change" \
  "$(grep -c "background='#00ff00'" <<<"$line_after")" "1"

# ---- a theme with an empty backgrounds dir is still listed, without an icon

emptybg_themes="$TMP/themes-emptybg"
must_be_fixture "$emptybg_themes"
mkdir -p "$emptybg_themes/nowall/backgrounds"

emptybg_cache="$TMP/cache-emptybg"
emptybg_line=$(THEMES_DIR="$emptybg_themes" XDG_CACHE_HOME="$emptybg_cache" bash "$PICKER")

check "a theme with an empty backgrounds dir is emitted" \
  "$([[ -n $emptybg_line ]] && echo nonempty || echo empty)" "nonempty"
check "a theme with an empty backgrounds dir carries no icon separator" \
  "$(printf '%s' "$emptybg_line" | python3 -c "import sys; print(sys.stdin.buffer.read().count(b'\x00icon\x1f'))")" "0"

# ---- no ImageMagick: the feed still emits, icon path falls back to source -

nomagick_themes="$TMP/themes-nomagick"
must_be_fixture "$nomagick_themes"
mkdir -p "$nomagick_themes/solo/backgrounds"
make_wallpaper "$nomagick_themes/solo/backgrounds/wall.jpg"

nomagick_cache="$TMP/cache-nomagick"

bin_no_magick="$TMP/bin-no-magick"
mkdir -p "$bin_no_magick"
for u in mkdir sed cut head find sort basename mktemp md5sum rm cat stat; do
  ln -s "$(command -v "$u")" "$bin_no_magick/$u"
done

nomagick_out="$TMP/nomagick-out"
env -i "PATH=$bin_no_magick" "THEMES_DIR=$nomagick_themes" \
  "XDG_CACHE_HOME=$nomagick_cache" /usr/bin/bash "$PICKER" >"$nomagick_out"

check "with no magick on PATH the feed still emits a line" \
  "$([[ -s $nomagick_out ]] && echo nonempty || echo empty)" "nonempty"

# ---- the swatch keys produce distinct colours on every shipped theme -----
# accent and color4 are the same value in most themes, so an earlier key set
# wasted one of the four swatches. The key list is read out of the picker
# rather than repeated here, so changing it re-runs this check against it.

keys=$(sed -n 's/^[[:space:]]*for key in \(.*\); do$/\1/p' "$REPO/.local/bin/hyprsimple-theme-picker.sh" | head -n 1)
dup_themes=0
for colors in "$REPO"/.config/hypr/themes/*/colors.toml; do
  vals=""
  for k in $keys; do
    vals+="$(sed -n "s/^${k}[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$colors" | head -n 1)"$'\n'
  done
  distinct=$(printf '%s' "$vals" | grep -c .)
  unique=$(printf '%s' "$vals" | sort -u | grep -c .)
  [[ $unique -lt $distinct ]] && dup_themes=$((dup_themes + 1))
done

check "the picker's swatch keys are distinct on every shipped theme" "$dup_themes" "0"

# ---- every key from the theme producer names a directory in the fixture --

tp_dirs_ok=yes
while IFS=$'\t' read -r tp_key _ _; do
  [[ -d "$three_themes/$tp_key" ]] || tp_dirs_ok=no
done <"$out_three"
check "every key from the theme producer names a directory in the fixture themes directory" "$tp_dirs_ok" "yes"

# ---- the theme producer emits one row per theme directory, excluding templates

tmpl_themes="$TMP/themes-templates"
must_be_fixture "$tmpl_themes"
mkdir -p "$tmpl_themes/one" "$tmpl_themes/two" "$tmpl_themes/three" \
  "$tmpl_themes/templates" "$tmpl_themes/templates.user"
tmpl_out="$TMP/out-templates"
THEMES_DIR="$tmpl_themes" XDG_CACHE_HOME="$TMP/cache-templates" bash "$PICKER" >"$tmpl_out"
check "the theme producer excludes templates and templates.user" "$(wc -l <"$tmpl_out")" "3"

# ---- the wallpaper producer's keys, and its label shape --------------------

wp_theme="$TMP/wp-theme"
must_be_fixture "$wp_theme"
mkdir -p "$wp_theme/backgrounds"
make_wallpaper "$wp_theme/backgrounds/0-morning-breeze.jpg"
make_wallpaper "$wp_theme/backgrounds/1-evening-glow.jpg"

# Fed through HOME, not XDG_CACHE_HOME. This suite used to set XDG_CACHE_HOME,
# and passed, because the picker was the one script in the set that read it.
# Every script that writes the record writes it to $HOME/.cache, so a machine
# with XDG_CACHE_HOME set had the picker reading a path nobody writes. The
# suite agreeing with the picker is what kept that invisible.
wp_home="$TMP/home-wp"
wp_cache="$wp_home/.cache"
must_be_fixture "$wp_cache"
mkdir -p "$wp_cache"
printf '%s\n' "$wp_theme/backgrounds/0-morning-breeze.jpg" >"$wp_cache/current_wallpaper_path"

wp_out="$TMP/out-wp"
HOME="$wp_home" bash "$WALLPAPER_PICKER" >"$wp_out"

# And XDG_CACHE_HOME pointing somewhere else changes nothing, because the
# writers do not read it either.
wp_xdg_out="$TMP/out-wp-xdg"
HOME="$wp_home" XDG_CACHE_HOME="$TMP/somewhere-else" bash "$WALLPAPER_PICKER" >"$wp_xdg_out"
check "XDG_CACHE_HOME does not move the record out from under the picker" \
  "$(cmp -s "$wp_out" "$wp_xdg_out" && echo same || echo diverged)" "same"

# The record can be gone: a fresh install has never written one. dirname of an
# empty string is ".", and "." is a directory, so the directory check passed
# and the picker listed whatever jpg and png files were in the working
# directory, offered as the current theme's wallpapers.
norec_home="$TMP/home-norecord"
mkdir -p "$norec_home/.cache" "$TMP/cwd-with-images"
make_wallpaper "$TMP/cwd-with-images/not-a-wallpaper.png"
norec_out=$(cd "$TMP/cwd-with-images" && HOME="$norec_home" bash "$WALLPAPER_PICKER")
check "with no record, the picker emits nothing rather than the working directory" \
  "$norec_out" ""

# Anti-vacuity: the same working directory does produce rows when it is the
# recorded theme, so the check above is about the missing record and not about
# find coming up empty.
canary_home="$TMP/home-canary"
mkdir -p "$canary_home/.cache"
printf '%s\n' "$TMP/cwd-with-images/not-a-wallpaper.png" >"$canary_home/.cache/current_wallpaper_path"
canary_out=$(cd "$TMP/cwd-with-images" && HOME="$canary_home" bash "$WALLPAPER_PICKER")
check "and that same directory does produce a row when it is the recorded one" \
  "$(printf '%s' "$canary_out" | wc -l)" "0"
check "which is one row" "$(printf '%s\n' "$canary_out" | grep -c 'not-a-wallpaper')" "1"

# Neither script keeps a readlink fallback on current_wallpaper. It read as a
# safety net and could never fire: every writer copies the picture there rather
# than linking to it, so readlink -f returns that copy's own path and the theme
# directory comes out as the user's home.
fb_home="$TMP/home-fallback"
mkdir -p "$fb_home/.cache"
cp "$wp_theme/backgrounds/0-morning-breeze.jpg" "$fb_home/.cache/current_wallpaper"
fb_out=$(HOME="$fb_home" bash "$WALLPAPER_PICKER")
check "a copy at current_wallpaper with no record resolves nothing, so the picker emits nothing" \
  "$fb_out" ""
check "and the dead readlink fallback is gone from both scripts" \
  "$(cat "$WALLPAPER_PICKER" "$WALLPAPER_SWITCHER" | sed 's/#.*//' | grep -c 'readlink')" "0"
check "while the writers really do copy rather than link, which is why it was dead" \
  "$(sed 's/#.*//' "$WALLPAPER_SWITCHER" | grep -c 'cp "$SELECTED" "$CACHE_DIR/current_wallpaper"')" "1"

wp_keys_ok=yes
while IFS=$'\t' read -r wp_key _ _; do
  [[ -f $wp_key ]] || wp_keys_ok=no
done <"$wp_out"
check "every key from the wallpaper producer is a file in the fixture backgrounds directory" "$wp_keys_ok" "yes"

wp_label=$(cut -f2 "$wp_out" | head -n 1)
check "the wallpaper producer's label has no extension and no leading sort prefix" "$wp_label" "morning breeze"

# ---- theme-switcher.sh no longer transforms the picker's output -----------

check "grep finds no sed or tr applied to the picker output in theme-switcher.sh" \
  "$(grep -A2 'hyprsimple-theme-picker.sh"' "$REPO/.local/bin/theme-switcher.sh" | grep -cE '^[[:space:]]*(sed|tr) ')" "0"

# ---- a theme with exactly one wallpaper still opens the picker -------------
# It used to stop with "Only one wallpaper in this theme", which was true while
# a picker could only choose. The picker is also where a wallpaper is added and
# where cycling is switched on, and 37 of the 40 shipped themes have one
# wallpaper, so that notice shut the door on nearly every theme.

ws_home="$TMP/ws-home"
must_be_fixture "$ws_home"
mkdir -p "$ws_home/.local/bin" "$ws_home/.cache"
# hyprsimple-require.sh too: the scripts test for their helpers before
# sourcing them, so a fixture without it stops rather than running.
cp "$REPO/.local/bin/hypr-helpers.sh" "$REPO/.local/bin/hyprsimple-require.sh" \
  "$ws_home/.local/bin/"

ws_marker="$TMP/picker-invoked-marker"

ws_theme_bg="$TMP/ws-theme/backgrounds"
must_be_fixture "$TMP/ws-theme"
mkdir -p "$ws_theme_bg"
make_wallpaper "$ws_theme_bg/only.jpg"
printf '%s\n' "$ws_theme_bg/only.jpg" >"$ws_home/.cache/current_wallpaper_path"

ws_notify_bin="$TMP/ws-notify-bin"
mkdir -p "$ws_notify_bin"
printf '#!/bin/sh\nexit 0\n' >"$ws_notify_bin/notify-send"
# The picker is a panel of the bar, opened through qs. A stand-in, so the real
# one is never asked to open it, which leaves a mark when it is called.
printf '#!/bin/sh\ntouch "%s"\n' "$ws_marker" >"$ws_notify_bin/qs"
chmod +x "$ws_notify_bin/notify-send" "$ws_notify_bin/qs"

PATH="$ws_notify_bin:$PATH" HOME="$ws_home" bash "$WALLPAPER_SWITCHER" pick >/dev/null 2>&1
ws_exit=$?

check "a fixture theme holding exactly one wallpaper makes wallpaper-switcher.sh pick exit 0" "$ws_exit" "0"
check "a fixture theme holding exactly one wallpaper still opens the picker" \
  "$([[ -e $ws_marker ]] && echo invoked || echo not-invoked)" "invoked"

# next has nowhere to go with one wallpaper, and still says so without opening anything.
rm -f "$ws_marker"
PATH="$ws_notify_bin:$PATH" HOME="$ws_home" bash "$WALLPAPER_SWITCHER" next >/dev/null 2>&1
check "next on a theme with one wallpaper exits 0" "$?" "0"
check "and opens nothing" "$([[ -e $ws_marker ]] && echo invoked || echo not-invoked)" "not-invoked"

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
