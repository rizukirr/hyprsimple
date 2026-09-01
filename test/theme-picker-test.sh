#!/bin/bash
# Checks the theme picker's dmenu feed and the migration that retires the
# launcher's theme mode. Never touches the real ~/.config.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PICKER="$REPO/.local/bin/hyprsimple-theme-picker.sh"
MIGRATION="$REPO/migrations/1788100840.sh"
SHIPPED_LAUNCHER="$REPO/test/fixtures/rofi/launcher-config.rasi.shipped"
SHIPPED_ROOT="$REPO/test/fixtures/rofi/config.rasi.shipped"
IMAGE_PICKER="$REPO/.local/bin/hyprsimple-image-picker.sh"
WALLPAPER_PICKER="$REPO/.local/bin/hyprsimple-wallpaper-picker.sh"
WALLPAPER_SWITCHER="$REPO/.local/bin/wallpaper-switcher.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# A stub rofi on PATH. hyprsimple-image-picker.sh invokes rofi by name, so this
# suite must put a real executable ahead of the real rofi on PATH rather than
# ever run it: the real one would open a window on the maintainer's screen.
# It reports the selection via $ROFI_STUB_INDEX and, when $ROFI_STUB_CAPTURE
# is set, saves what it was fed byte for byte. That capture is the only way to
# see the NUL icon separator: it cannot survive a shell variable or command
# substitution, which is what let a picker that sent zero separators still
# pass every other check.
bin_rofi="$TMP/bin-rofi"
mkdir -p "$bin_rofi"
cat >"$bin_rofi/rofi" <<'STUB'
#!/bin/bash
if [[ -n ${ROFI_STUB_CAPTURE:-} ]]; then
  cat >"$ROFI_STUB_CAPTURE"
else
  cat >/dev/null
fi
printf '%s\n' "${ROFI_STUB_INDEX:-0}"
STUB
chmod +x "$bin_rofi/rofi"
export PATH="$bin_rofi:$PATH"

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

# ---- every row rofi receives for an existing image carries the icon
# separator and a path that exists (the theme picker itself does no
# thumbnailing any more; this now lives in hyprsimple-image-picker.sh and is
# only observable by capturing rofi's stdin) -------------------------------

rows_three=$(python3 -c "
import sys
lines = open(sys.argv[1]).read().splitlines()
for l in lines:
    key, label, image = l.split('\t')
    print(f'{key}\t{label}\t{image}')
" "$out_three")

rt1_cache="$TMP/cache-rt1"
rt1_capture="$TMP/capture-rt1"
ROFI_STUB_INDEX=0 ROFI_STUB_CAPTURE="$rt1_capture" \
  XDG_CACHE_HOME="$rt1_cache" bash "$IMAGE_PICKER" <<<"$rows_three" >/dev/null

rt1_result=$(python3 - "$rt1_capture" <<'PY'
import sys, os
data = open(sys.argv[1], 'rb').read()
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
check "every emitted line carries the icon separator and a path that exists" "$rt1_result" "yes"

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
# Thumbnailing moved from the theme picker to the image picker, so this now
# drives hyprsimple-image-picker.sh with rows the test constructs.

cache_src_dir="$TMP/cache-src"
must_be_fixture "$cache_src_dir"
mkdir -p "$cache_src_dir"
make_wallpaper "$cache_src_dir/one.jpg"
make_wallpaper "$cache_src_dir/two.jpg"

cache_dir_base="$TMP/cache-mtime"
must_be_fixture "$cache_dir_base"
hash_one=$(printf '%s' "$cache_src_dir/one.jpg" | md5sum | cut -d' ' -f1)
hash_two=$(printf '%s' "$cache_src_dir/two.jpg" | md5sum | cut -d' ' -f1)
thumb_one="$cache_dir_base/hyprsimple/image-previews/$hash_one.jpg"
thumb_two="$cache_dir_base/hyprsimple/image-previews/$hash_two.jpg"
cache_rows=$(printf 'one\tOne\t%s\ntwo\tTwo\t%s\n' "$cache_src_dir/one.jpg" "$cache_src_dir/two.jpg")

ROFI_STUB_INDEX=0 XDG_CACHE_HOME="$cache_dir_base" bash "$IMAGE_PICKER" <<<"$cache_rows" >/dev/null

mtime_one_1=$(stat -c %Y "$thumb_one")
mtime_two_1=$(stat -c %Y "$thumb_two")

ROFI_STUB_INDEX=0 XDG_CACHE_HOME="$cache_dir_base" bash "$IMAGE_PICKER" <<<"$cache_rows" >/dev/null

mtime_one_2=$(stat -c %Y "$thumb_one")
mtime_two_2=$(stat -c %Y "$thumb_two")

check "a second run leaves thumbnail one's mtime unchanged" "$mtime_one_2" "$mtime_one_1"
check "a second run leaves thumbnail two's mtime unchanged" "$mtime_two_2" "$mtime_two_1"

# Touching only one source wallpaper should regenerate only its thumbnail.
# The sleep guarantees the regenerated thumbnail lands in a different second
# than the one being compared against; mtime has only second resolution here.
sleep 1
touch -d '+1 hour' "$cache_src_dir/one.jpg"

ROFI_STUB_INDEX=0 XDG_CACHE_HOME="$cache_dir_base" bash "$IMAGE_PICKER" <<<"$cache_rows" >/dev/null

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
for u in mkdir sed cut head find sort basename mktemp md5sum rm cat stat; do
  ln -s "$(command -v "$u")" "$bin_no_magick/$u"
done

nomagick_out="$TMP/nomagick-out"
env -i "PATH=$bin_no_magick" "THEMES_DIR=$nomagick_themes" \
  "XDG_CACHE_HOME=$nomagick_cache" /usr/bin/bash "$PICKER" >"$nomagick_out"

check "with no magick on PATH the feed still emits a line" \
  "$([[ -s $nomagick_out ]] && echo nonempty || echo empty)" "nonempty"

# Thumbnailing, and its ImageMagick fallback, moved to the image picker. Drive
# it directly with a bare PATH (no magick, no convert) plus just the rofi stub
# and the utilities it needs, and read the icon path back out of rofi's
# captured stdin.
im_nomagick_out="$TMP/im-nomagick-out"
im_nomagick_rows=$(printf 'solo\tSolo\t%s\n' "$nomagick_themes/solo/backgrounds/wall.jpg")
env -i "PATH=$bin_no_magick:$bin_rofi" "XDG_CACHE_HOME=$nomagick_cache" \
  ROFI_STUB_INDEX=0 ROFI_STUB_CAPTURE="$im_nomagick_out" \
  /usr/bin/bash "$IMAGE_PICKER" <<<"$im_nomagick_rows" >/dev/null

nomagick_icon=$(python3 -c "
data = open('$im_nomagick_out', 'rb').read()
parts = data.split(b'\x00icon\x1f', 1)
print(parts[1].decode().strip() if len(parts) > 1 else '')
")

check "with no magick on PATH the icon path is the source wallpaper" \
  "$([[ $nomagick_icon -ef "$nomagick_themes/solo/backgrounds/wall.jpg" ]] && echo same || echo different)" "same"

# ---- the shipped launcher no longer offers a themes mode -------------------

check "the shipped launcher/config.rasi's modi contains no themes: mode" \
  "$(grep 'modi:' "$REPO/.config/rofi/launcher/config.rasi" | grep -c 'themes:')" "0"

# default/ is searched too. The rofi defaults moved there in the import split,
# so grepping .config alone would pass no matter what those files contain.
check "no shipped file under .config or default mentions theme-selector" \
  "$(grep -rl 'theme-selector' "$REPO/.config" "$REPO/default" 2>/dev/null | wc -l)" "0"

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

# ---- a key with an uppercase letter and a space round-trips byte-identical

rt_rows=$(printf 'alpha\tAlpha\t\nMy Theme\tMy Theme\t\ngamma\tGamma\t\n')

rt_key=$(ROFI_STUB_INDEX=1 XDG_CACHE_HOME="$TMP/cache-rt-key" bash "$IMAGE_PICKER" <<<"$rt_rows")
check "a key containing an uppercase letter and a space is returned byte-identical, with rofi stubbed to select a known index" \
  "$rt_key" "My Theme"

# ---- selecting index 0, then a later index, prints that row's key both times

rt_key_0=$(ROFI_STUB_INDEX=0 XDG_CACHE_HOME="$TMP/cache-rt-multi" bash "$IMAGE_PICKER" <<<"$rt_rows")
rt_key_2=$(ROFI_STUB_INDEX=2 XDG_CACHE_HOME="$TMP/cache-rt-multi" bash "$IMAGE_PICKER" <<<"$rt_rows")
check "with rofi stubbed to select index 0 and then a later index, the printed key is that row's key both times" \
  "$rt_key_0|$rt_key_2" "alpha|gamma"

# ---- every key from the theme producer names a directory in the fixture --

tp_dirs_ok=yes
while IFS=$'\t' read -r tp_key _ _; do
  [[ -d "$three_themes/$tp_key" ]] || tp_dirs_ok=no
done <"$out_three"
check "every key from the theme producer names a directory in the fixture themes directory" "$tp_dirs_ok" "yes"

# ---- the theme producer emits one row per theme directory, excluding templates

tmpl_themes="$TMP/themes-templates"
must_be_fixture "$tmpl_themes"
mkdir -p "$tmpl_themes/one" "$tmpl_themes/two" "$tmpl_themes/three" "$tmpl_themes/templates"
tmpl_out="$TMP/out-templates"
THEMES_DIR="$tmpl_themes" XDG_CACHE_HOME="$TMP/cache-templates" bash "$PICKER" >"$tmpl_out"
check "the theme producer emits one row per theme directory, excluding templates" "$(wc -l <"$tmpl_out")" "3"

# ---- the wallpaper producer's keys, and its label shape --------------------

wp_theme="$TMP/wp-theme"
must_be_fixture "$wp_theme"
mkdir -p "$wp_theme/backgrounds"
make_wallpaper "$wp_theme/backgrounds/0-morning-breeze.jpg"
make_wallpaper "$wp_theme/backgrounds/1-evening-glow.jpg"

wp_cache="$TMP/cache-wp"
must_be_fixture "$wp_cache"
mkdir -p "$wp_cache"
printf '%s\n' "$wp_theme/backgrounds/0-morning-breeze.jpg" >"$wp_cache/current_wallpaper_path"

wp_out="$TMP/out-wp"
XDG_CACHE_HOME="$wp_cache" bash "$WALLPAPER_PICKER" >"$wp_out"

wp_keys_ok=yes
while IFS=$'\t' read -r wp_key _ _; do
  [[ -f $wp_key ]] || wp_keys_ok=no
done <"$wp_out"
check "every key from the wallpaper producer is a file in the fixture backgrounds directory" "$wp_keys_ok" "yes"

wp_label=$(cut -f2 "$wp_out" | head -n 1)
check "the wallpaper producer's label has no extension and no leading sort prefix" "$wp_label" "morning breeze"

# ---- two producers naming the same image share one cache entry ------------

dup_img="$TMP/dup-img/pic.jpg"
mkdir -p "$TMP/dup-img"
make_wallpaper "$dup_img"
dup_cache="$TMP/cache-dup"
dup_rows=$(printf 'from-theme\tFrom Theme\t%s\nfrom-wallpaper\tFrom Wallpaper\t%s\n' "$dup_img" "$dup_img")
ROFI_STUB_INDEX=0 XDG_CACHE_HOME="$dup_cache" bash "$IMAGE_PICKER" <<<"$dup_rows" >/dev/null
dup_count=$(find "$dup_cache/hyprsimple/image-previews" -type f | wc -l)
check "two producers naming the same image cause one cache entry to exist, not two" "$dup_count" "1"

# ---- theme-switcher.sh no longer transforms the picker's output -----------

check "grep finds no sed or tr applied to the picker output in theme-switcher.sh" \
  "$(grep -A2 'hyprsimple-theme-picker.sh"' "$REPO/.local/bin/theme-switcher.sh" | grep -cE '^[[:space:]]*(sed|tr) ')" "0"

# ---- the image picker itself degrades without ImageMagick -----------------

nomagick2_dir="$TMP/nomagick2"
mkdir -p "$nomagick2_dir"
make_wallpaper "$nomagick2_dir/pic.jpg"
nomagick2_rows=$(printf 'solo\tSolo\t%s\n' "$nomagick2_dir/pic.jpg")
nomagick2_out=$(env -i "PATH=$bin_no_magick:$bin_rofi" "XDG_CACHE_HOME=$TMP/cache-nomagick2" \
  ROFI_STUB_INDEX=0 /usr/bin/bash "$IMAGE_PICKER" <<<"$nomagick2_rows")
check "with no ImageMagick on PATH, the picker still prints a key" "$nomagick2_out" "solo"

# ---- a row whose image is missing is still selectable ----------------------

missing_rows=$(printf 'exists\tExists\t%s\nmissing\tMissing\t/no/such/path.jpg\n' "$dup_img")
missing_out=$(ROFI_STUB_INDEX=1 XDG_CACHE_HOME="$TMP/cache-missing" bash "$IMAGE_PICKER" <<<"$missing_rows")
check "a row whose image path does not exist is still selectable, checked by stubbing rofi to select it" \
  "$missing_out" "missing"

# ---- what actually reaches rofi carries the NUL separator ------------------
# An exit status cannot see this: a picker that silently dropped every
# separator would still return the correct key on selection. Only capturing
# rofi's stdin catches it.

sep_img1="$TMP/sep/one.jpg"
sep_img2="$TMP/sep/two.jpg"
mkdir -p "$TMP/sep"
make_wallpaper "$sep_img1"
make_wallpaper "$sep_img2"
sep_rows=$(printf 'one\tOne\t%s\ntwo\tTwo\t%s\n' "$sep_img1" "$sep_img2")
sep_capture="$TMP/capture-sep"
ROFI_STUB_INDEX=0 ROFI_STUB_CAPTURE="$sep_capture" XDG_CACHE_HOME="$TMP/cache-sep" \
  bash "$IMAGE_PICKER" <<<"$sep_rows" >/dev/null

sep_result=$(python3 -c "
import os
data = open('$sep_capture', 'rb').read()
lines = [l for l in data.split(b'\n') if l]
count = data.count(b'\x00icon\x1f')
ok = count == 2 and all(
    os.path.exists(l.split(b'\x00icon\x1f', 1)[1])
    for l in lines if b'\x00icon\x1f' in l
)
print('yes' if ok else 'no')
")
check "every row rofi receives for an existing image carries the NUL icon separator and a path that exists" \
  "$sep_result" "yes"

# ---- an unwritable cache directory still yields a usable picker -----------

unwritable_dir="$TMP/cache-unwritable"
mkdir -p "$unwritable_dir"
chmod 000 "$unwritable_dir"
uw_rows=$(printf 'solo\tSolo\t%s\n' "$dup_img")
uw_out=$(ROFI_STUB_INDEX=0 XDG_CACHE_HOME="$unwritable_dir" bash "$IMAGE_PICKER" <<<"$uw_rows")
chmod 755 "$unwritable_dir"
check "with the cache directory made unwritable, the picker still prints a key" "$uw_out" "solo"

# ---- a theme with exactly one wallpaper skips the picker entirely ---------
# Four shipped themes have exactly one wallpaper, so wallpaper-switcher.sh's
# early exit is reached in practice, not just in this fixture.

ws_home="$TMP/ws-home"
must_be_fixture "$ws_home"
mkdir -p "$ws_home/.local/bin" "$ws_home/.cache"
cp "$REPO/.local/bin/hypr-helpers.sh" "$ws_home/.local/bin/hypr-helpers.sh"

ws_marker="$TMP/picker-invoked-marker"
cat >"$ws_home/.local/bin/hyprsimple-image-picker.sh" <<STUB2
#!/bin/bash
touch "$ws_marker"
STUB2
chmod +x "$ws_home/.local/bin/hyprsimple-image-picker.sh"

ws_theme_bg="$TMP/ws-theme/backgrounds"
must_be_fixture "$TMP/ws-theme"
mkdir -p "$ws_theme_bg"
make_wallpaper "$ws_theme_bg/only.jpg"
printf '%s\n' "$ws_theme_bg/only.jpg" >"$ws_home/.cache/current_wallpaper_path"

ws_notify_bin="$TMP/ws-notify-bin"
mkdir -p "$ws_notify_bin"
printf '#!/bin/sh\nexit 0\n' >"$ws_notify_bin/notify-send"
chmod +x "$ws_notify_bin/notify-send"

PATH="$ws_notify_bin:$PATH" HOME="$ws_home" bash "$WALLPAPER_SWITCHER" pick >/dev/null 2>&1
ws_exit=$?

check "a fixture theme holding exactly one wallpaper makes wallpaper-switcher.sh pick exit 0" "$ws_exit" "0"
check "a fixture theme holding exactly one wallpaper makes wallpaper-switcher.sh pick skip invoking the picker" \
  "$([[ -e $ws_marker ]] && echo invoked || echo not-invoked)" "not-invoked"

if ((failures > 0)); then printf '\n%s check(s) failed\n' "$failures" >&2; exit 1; fi
printf '\nall checks passed\n'
