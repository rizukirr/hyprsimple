#!/bin/bash
# Checks the theme picker's dmenu feed and the migration that retires the
# launcher's theme mode. Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PICKER="$REPO/.local/bin/hyprsimple-theme-picker.sh"
MIGRATION="$REPO/migrations/1788100840.sh"
SHIPPED_LAUNCHER="$REPO/test/fixtures/rofi/launcher-config.rasi.shipped"
SHIPPED_ROOT="$REPO/test/fixtures/rofi/config.rasi.shipped"
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

make_wallpaper() { magick -size 400x300 xc:gray "$1"; }

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

# ---- every emitted line carries the icon separator and a real path --------
# NUL bytes cannot be given as shell arguments, so this is checked in
# python3, which can express the separator and split records on the real
# newline byte.

b_result=$(python3 - "$out_three" <<'PY'
import sys, os
path = sys.argv[1]
data = open(path, 'rb').read()
lines = [l for l in data.split(b'\n') if l]
ok = True
for l in lines:
    if b'\x00icon\x1f' not in l:
        ok = False
        break
    icon_path = l.split(b'\x00icon\x1f', 1)[1]
    if not os.path.exists(icon_path):
        ok = False
        break
print('yes' if ok else 'no')
PY
)
check "every emitted line carries the icon separator and a path that exists" "$b_result" "yes"

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

# ---- caching: a second run touches no thumbnail, a changed source does ----

cache_themes="$TMP/themes-cache"
must_be_fixture "$cache_themes"
mkdir -p "$cache_themes/one/backgrounds" "$cache_themes/two/backgrounds"
make_wallpaper "$cache_themes/one/backgrounds/wall.jpg"
make_wallpaper "$cache_themes/two/backgrounds/wall.jpg"

cache_dir_base="$TMP/cache-mtime"
must_be_fixture "$cache_dir_base"
thumb_one="$cache_dir_base/hyprsimple/theme-previews/one.jpg"
thumb_two="$cache_dir_base/hyprsimple/theme-previews/two.jpg"

THEMES_DIR="$cache_themes" XDG_CACHE_HOME="$cache_dir_base" bash "$PICKER" >/dev/null

mtime_one_1=$(stat -c %Y "$thumb_one")
mtime_two_1=$(stat -c %Y "$thumb_two")

THEMES_DIR="$cache_themes" XDG_CACHE_HOME="$cache_dir_base" bash "$PICKER" >/dev/null

mtime_one_2=$(stat -c %Y "$thumb_one")
mtime_two_2=$(stat -c %Y "$thumb_two")

check "a second run leaves thumbnail one's mtime unchanged" "$mtime_one_2" "$mtime_one_1"
check "a second run leaves thumbnail two's mtime unchanged" "$mtime_two_2" "$mtime_two_1"

# Touching only one source wallpaper should regenerate only its thumbnail.
# The sleep guarantees the regenerated thumbnail lands in a different second
# than the one being compared against; mtime has only second resolution here.
sleep 1
touch -d '+1 hour' "$cache_themes/one/backgrounds/wall.jpg"

THEMES_DIR="$cache_themes" XDG_CACHE_HOME="$cache_dir_base" bash "$PICKER" >/dev/null

mtime_one_3=$(stat -c %Y "$thumb_one")
mtime_two_3=$(stat -c %Y "$thumb_two")

check "touching one source wallpaper regenerates its thumbnail" \
  "$([[ $mtime_one_3 != "$mtime_one_1" ]] && echo regenerated || echo unchanged)" "regenerated"
check "touching one source wallpaper leaves the other thumbnail's mtime alone" "$mtime_two_3" "$mtime_two_1"

# ---- no ImageMagick: the feed still emits, icon path falls back to source -

nomagick_themes="$TMP/themes-nomagick"
must_be_fixture "$nomagick_themes"
mkdir -p "$nomagick_themes/solo/backgrounds"
make_wallpaper "$nomagick_themes/solo/backgrounds/wall.jpg"

nomagick_cache="$TMP/cache-nomagick"

bin_no_magick="$TMP/bin-no-magick"
mkdir -p "$bin_no_magick"
for u in mkdir sed cut head find sort basename; do
  ln -s "$(command -v "$u")" "$bin_no_magick/$u"
done

nomagick_out="$TMP/nomagick-out"
env -i "PATH=$bin_no_magick" "THEMES_DIR=$nomagick_themes" \
  "XDG_CACHE_HOME=$nomagick_cache" /usr/bin/bash "$PICKER" >"$nomagick_out"

check "with no magick on PATH the feed still emits a line" \
  "$([[ -s $nomagick_out ]] && echo nonempty || echo empty)" "nonempty"

nomagick_icon=$(python3 -c "
data = open('$nomagick_out', 'rb').read()
print(data.split(b'\x00icon\x1f', 1)[1].decode().strip())
")

check "with no magick on PATH the icon path is the source wallpaper" \
  "$([[ $nomagick_icon -ef "$nomagick_themes/solo/backgrounds/wall.jpg" ]] && echo same || echo different)" "same"

# ---- the shipped launcher no longer offers a themes mode -------------------

check "the shipped launcher/config.rasi's modi contains no themes: mode" \
  "$(grep 'modi:' "$REPO/.config/rofi/launcher/config.rasi" | grep -c 'themes:')" "0"

check "no shipped file under .config mentions theme-selector" \
  "$(grep -rl 'theme-selector' "$REPO/.config" 2>/dev/null | wc -l)" "0"

# ---- the migration ----------------------------------------------------

install_root="$TMP/install-migrate"
must_be_fixture "$install_root"
mkdir -p "$install_root/.config/rofi/launcher" "$install_root/.config/rofi/theme-picker"
cp "$REPO/.config/rofi/launcher/config.rasi" "$install_root/.config/rofi/launcher/config.rasi"
cp "$REPO/.config/rofi/config.rasi" "$install_root/.config/rofi/config.rasi"
cp "$REPO/.config/rofi/theme-picker/style.rasi" "$install_root/.config/rofi/theme-picker/style.rasi"

# a home lacking the picker's rofi theme gets it installed
home_missing_style="$TMP/home-missing-style"
must_be_fixture "$home_missing_style"
mkdir -p "$home_missing_style/.config/rofi"

HOME="$home_missing_style" HYPRSIMPLE_PATH="$install_root" bash "$MIGRATION" >/dev/null 2>&1

check "the migration installs theme-picker/style.rasi when absent" \
  "$([[ -f $home_missing_style/.config/rofi/theme-picker/style.rasi ]] && echo installed || echo missing)" "installed"

# an existing theme-picker/style.rasi is never overwritten
home_own_style="$TMP/home-own-style"
must_be_fixture "$home_own_style"
mkdir -p "$home_own_style/.config/rofi/theme-picker"
printf '/* MY OWN STYLE MARKER */\n' >"$home_own_style/.config/rofi/theme-picker/style.rasi"

HOME="$home_own_style" HYPRSIMPLE_PATH="$install_root" bash "$MIGRATION" >/dev/null 2>&1

check "the migration does not overwrite an existing theme-picker/style.rasi" \
  "$(grep -c 'MY OWN STYLE MARKER' "$home_own_style/.config/rofi/theme-picker/style.rasi")" "1"

# a fixture matching a shipped checksum is replaced by the current version
home_pristine="$TMP/home-pristine"
must_be_fixture "$home_pristine"
mkdir -p "$home_pristine/.config/rofi/launcher"
cp "$SHIPPED_LAUNCHER" "$home_pristine/.config/rofi/launcher/config.rasi"
cp "$SHIPPED_ROOT" "$home_pristine/.config/rofi/config.rasi"

HOME="$home_pristine" HYPRSIMPLE_PATH="$install_root" bash "$MIGRATION" >/dev/null 2>&1

check "a pristine launcher/config.rasi is replaced by the install's version" \
  "$(cmp -s "$home_pristine/.config/rofi/launcher/config.rasi" "$install_root/.config/rofi/launcher/config.rasi" && echo same || echo different)" \
  "same"
check "a pristine config.rasi is replaced by the install's version" \
  "$(cmp -s "$home_pristine/.config/rofi/config.rasi" "$install_root/.config/rofi/config.rasi" && echo same || echo different)" \
  "same"

# a fixture matching no shipped checksum is left byte-unchanged
home_edited="$TMP/home-edited"
must_be_fixture "$home_edited"
mkdir -p "$home_edited/.config/rofi/launcher"
{ cat "$SHIPPED_LAUNCHER"; echo "// a user's own comment"; } >"$home_edited/.config/rofi/launcher/config.rasi"

edited_before=$(md5sum "$home_edited/.config/rofi/launcher/config.rasi" | cut -d' ' -f1)
HOME="$home_edited" HYPRSIMPLE_PATH="$install_root" bash "$MIGRATION" >/dev/null 2>&1
edited_after=$(md5sum "$home_edited/.config/rofi/launcher/config.rasi" | cut -d' ' -f1)

check "an edited launcher/config.rasi is byte-unchanged by the migration" "$edited_after" "$edited_before"

# a second migration run against an already-migrated home changes nothing
idem_before=$(find "$home_pristine" -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)
HOME="$home_pristine" HYPRSIMPLE_PATH="$install_root" bash "$MIGRATION" >/dev/null 2>&1
idem_after=$(find "$home_pristine" -type f -exec md5sum {} \; | sort | md5sum | cut -d' ' -f1)

check "a second migration run changes no file in the fixture home" "$idem_after" "$idem_before"

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
