#!/bin/bash
# The theme catalogue, and the migration that carries it to installs that
# already exist.
#
# The themes that came from omarchy are gone and the well known colorschemes
# are here instead, converted from the palettes Ghostty ships so the colours are
# each project's own rather than an approximation.
#
# ~/.config/hypr/themes is copied once at install, so a theme added later
# reaches nobody and one dropped later stays for ever. The migration syncs both
# directions and is driven here against throwaway homes. Nothing switches a
# theme on the machine running this: theme-switcher.sh and systemctl are stubs.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
THEMES="$REPO/.config/hypr/themes"
MIGRATION="$REPO/migrations/1789030000.sh"
FIXTURES="$REPO/test/fixtures/removed-themes"
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

BASH_BIN="$(command -v bash)"

mapfile -t names < <(
  for d in "$THEMES"/*/; do
    n=$(basename "$d")
    [[ $n == templates* ]] && continue
    printf '%s\n' "$n"
  done
)

if ((${#names[@]} < 35)); then
  fail "found ${#names[@]} themes, which is fewer than the catalogue has"
else
  pass "checking ${#names[@]} shipped themes"
fi

# ---- the omarchy themes are gone ---------------------------------------------

gone=()
for n in ethereal hackerman matte-black miasma osaka-jade ristretto vantablack white; do
  [[ -e "$THEMES/$n" ]] && gone+=("$n")
done
check "no theme that came from omarchy still ships" "${gone[*]:-}" ""
check "deep-sea, which is hyprsimple's own, stays" \
  "$([[ -d $THEMES/deep-sea ]] && echo present || echo missing)" "present"

# ---- every theme is complete --------------------------------------------------
#
# Read out of the directory rather than from a list here, so a theme added later
# is held to the same rules.

report=$(python3 - "$THEMES" <<'PYEOF'
import os, re, sys
root = sys.argv[1]
keys = ["accent", "cursor", "foreground", "background",
        "selection_foreground", "selection_background"] + [f"color{i}" for i in range(16)]

def rel(h):
    r, g, b = (int(h[i:i+2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def contrast(a, b):
    la, lb = sorted((rel(a), rel(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

bad = []
for name in sorted(os.listdir(root)):
    d = os.path.join(root, name)
    if name.startswith("templates") or not os.path.isdir(d):
        continue
    colors = os.path.join(d, "colors.toml")
    if not os.path.isfile(colors):
        bad.append(f"{name}: no colors.toml")
        continue
    vals = dict(re.findall(r'^(\w+)\s*=\s*"#([0-9A-Fa-f]{6})"\s*$',
                           open(colors).read(), re.M))
    missing = [k for k in keys if k not in vals]
    if missing:
        bad.append(f"{name}: colors.toml missing {','.join(missing)}")
        continue

    # The picker shows four swatches. Two the same wastes one of them.
    swatches = {vals["background"], vals["foreground"], vals["accent"], vals["color1"]}
    if len(swatches) < 4:
        bad.append(f"{name}: picker swatches not distinct")

    # The accent draws borders and selections on the theme's own background.
    if contrast(vals["accent"], vals["background"]) < 3.0:
        bad.append(f"{name}: accent contrast {contrast(vals['accent'], vals['background']):.1f}")

    # A light theme is marked by light.mode, and that has to agree with the
    # background it actually has, or GTK goes dark on a pale desktop.
    light_file = os.path.isfile(os.path.join(d, "light.mode"))
    light_bg = rel(vals["background"]) > 0.5
    if light_file != light_bg:
        bad.append(f"{name}: light.mode={light_file} but background luminance says light={light_bg}")

    if not any(os.path.isfile(os.path.join(d, f)) for f in ("icon-theme", "icons.theme")):
        bad.append(f"{name}: names no icon theme")
    else:
        f = "icon-theme" if os.path.isfile(os.path.join(d, "icon-theme")) else "icons.theme"
        icon = open(os.path.join(d, f)).read().strip()
        # Yaru and Papirus are the two icon themes hyprsimple installs, from
        # aur-packages.txt and packages.txt. Naming anything else sets an icon
        # theme that is not there, and gsettings takes it without complaint.
        if not re.fullmatch(r"(Yaru|Papirus)(-[A-Za-z]+)*", icon):
            bad.append(f"{name}: icon theme {icon!r} is not one hyprsimple installs")
        else:
            # Only where that icon family is installed at all. A CI runner has
            # /usr/share/icons with neither Yaru nor Papirus in it, and testing
            # for the directory alone failed every theme there.
            family = icon.split("-")[0]
            if os.path.isdir(f"/usr/share/icons/{family}") and not os.path.isdir(f"/usr/share/icons/{icon}"):
                bad.append(f"{name}: icon theme {icon!r} is not installed")

    bgdir = os.path.join(d, "backgrounds")
    entries = os.listdir(bgdir) if os.path.isdir(bgdir) else []
    if not entries:
        bad.append(f"{name}: no wallpaper")
    for e in entries:
        p = os.path.join(bgdir, e)
        if not os.path.exists(p):
            bad.append(f"{name}: wallpaper {e} does not resolve")
        if os.path.islink(p) and os.path.isabs(os.readlink(p)):
            bad.append(f"{name}: wallpaper {e} is an absolute symlink")
print("; ".join(bad))
PYEOF
)
check "every theme is complete and consistent" "$report" ""

lights=$(find "$THEMES" -maxdepth 2 -name light.mode | wc -l | tr -d ' ')
if ((lights < 5)); then
  fail "only $lights light themes, and removing white left none unless these are here"
else
  pass "$lights light themes ship"
fi

# The palettes come from Ghostty's catalogue, which is not installed on CI.
missing_ghostty=()
if [[ -d /usr/share/ghostty/themes ]]; then
  for n in "${names[@]}"; do
    f="$THEMES/$n/ghostty-theme"
    [[ -f $f ]] || continue
    name=$(cat "$f")
    [[ -f "/usr/share/ghostty/themes/$name" ]] || missing_ghostty+=("$n -> $name")
  done
  check "every ghostty-theme names a theme ghostty ships" "${missing_ghostty[*]:-}" ""
else
  pass "ghostty's themes are not installed here, so the names are not resolved"
fi

# ---- every theme's wallpaper is findable ---------------------------------------
#
# The scripts locate a wallpaper with find, and a symlink is not a regular file.
# `find -type f` therefore returned nothing for every theme whose wallpaper is a
# link, which is the 32 added with the catalogue: no preview in the theme
# picker, and nothing to set when switching to one.

rows=$(THEMES_DIR="$THEMES" XDG_CACHE_HOME="$TMP/picker-cache" \
  "$BASH_BIN" "$REPO/.local/bin/hyprsimple-theme-picker.sh" 2>/dev/null)
check "the picker lists every theme" "$(printf '%s\n' "$rows" | grep -c .)" "${#names[@]}"
check "and every row carries a wallpaper" \
  "$(printf '%s\n' "$rows" | awk -F'\t' '$3 == "" {print $1}' | paste -sd' ')" ""

# The rule rather than the four instances, so a scan added later is caught.
unfollowed=()
while IFS= read -r hit; do
  [[ -n $hit ]] && unfollowed+=("${hit%%:*}")
done < <(
  for f in "$REPO/.local/bin"/*.sh; do
    sed 's/^[[:space:]]*#.*//' "$f" |
      grep -nE 'find .*(backgrounds|BG_DIR)' |
      grep -v 'find -L' |
      sed "s|^|$(basename "$f"):|"
  done
)
check "every scan of a theme's backgrounds follows symlinks" "${unfollowed[*]:-}" ""

# ---- every wallpaper format works everywhere -----------------------------------
#
# The switchers matched *.png and *.jpg only while the pickers also took .jpeg,
# so a .jpeg wallpaper appeared in the grid and then could not be set, and a
# .webp one was invisible everywhere. hyprpaper links libwebp and reads all
# four, and ImageMagick makes thumbnails from all four.
#
# The sets are read out of the scripts, so a scan that drifts is caught.
formats_report=$(python3 - "$REPO" <<'PYEOF'
import glob, os, re, sys
repo = sys.argv[1]
want = {"jpg", "jpeg", "png", "webp"}
bad = []
found = 0
for path in sorted(glob.glob(os.path.join(repo, ".local/bin/*.sh"))):
    src = re.sub(r"^[ \t]*#.*$", "", open(path).read(), flags=re.M)
    for line in src.splitlines():
        if "find" not in line or ("backgrounds" not in line and "BG_DIR" not in line):
            continue
        found += 1
        exts = {e.lower() for e in re.findall(r"-i?name\s+[\"']\*\.([A-Za-z]+)[\"']", line)}
        # The formats may be on the next lines of the same command, so widen to
        # the whole statement when the line alone names none.
        if not exts:
            start = src.index(line)
            exts = {e.lower() for e in re.findall(r"-i?name\s+[\"']\*\.([A-Za-z]+)[\"']", src[start:start + 400])}
        if exts != want:
            bad.append(f"{os.path.basename(path)}: {sorted(exts) or 'none'}")
if found < 4:
    bad.append(f"only {found} wallpaper scans found, which is fewer than there are")
print("; ".join(bad))
PYEOF
)
check "every wallpaper scan accepts jpg, jpeg, png and webp" "$formats_report" ""

# Driven rather than only read: a theme whose only wallpaper is a webp has to
# reach the picker.
webp_themes="$TMP/webp-themes/themes"
mkdir -p "$webp_themes/webponly/backgrounds"
cp "$THEMES/deep-sea/colors.toml" "$webp_themes/webponly/"
printf 'not really an image\n' >"$webp_themes/webponly/backgrounds/0-wall.webp"
webp_row=$(THEMES_DIR="$webp_themes" XDG_CACHE_HOME="$TMP/webp-cache" \
  "$BASH_BIN" "$REPO/.local/bin/hyprsimple-theme-picker.sh" 2>/dev/null)
check "a theme whose only wallpaper is a webp is listed with it" \
  "$(printf '%s\n' "$webp_row" | awk -F'\t' '{print $3}' | grep -c '0-wall.webp')" "1"

# rofi paints its launcher and power menu background through gdk-pixbuf, which
# reads webp only with this loader installed.
check "the webp pixbuf loader is installed for rofi" \
  "$(grep -cx 'webp-pixbuf-loader' "$REPO/packages.txt")" "1"

# ---- the interface is readable on every theme ---------------------------------
#
# The templates pasted palette slots straight into interface text, with nothing
# checking they land on the surface they are drawn on. colour0 is the terminal's
# black: on a dark theme a near-black behind light text, on a light theme still
# black while the text is dark. Measured before the fix, 37 of 40 themes had at
# least one pair below 3:1 and every light theme did, catppuccin-latte at 1.3
# on its waybar widgets, everforest-light at 1.0 on its selected rofi row.
#
# Every theme is rendered through the real renderer and the generated files are
# measured, rather than the rule being repeated here.

ui_report=$(python3 - "$THEMES" "$REPO" "$TMP" <<'PYEOF'
import os, re, shutil, subprocess, sys
themes, repo, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
home = os.path.join(tmp, "render-home")
os.makedirs(home, exist_ok=True)

def rel(h):
    h = h.lstrip("#")
    r, g, b = (int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))
    f = lambda c: c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
    return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b)

def contrast(a, b):
    la, lb = sorted((rel(a), rel(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)

bad = []
for name in sorted(os.listdir(themes)):
    d = os.path.join(themes, name)
    if name.startswith("templates") or not os.path.isdir(d):
        continue
    work = os.path.join(tmp, "render", name)
    os.makedirs(work, exist_ok=True)
    shutil.copy(os.path.join(d, "colors.toml"), work)
    subprocess.run([os.path.join(repo, ".local/bin/theme-apply-templates.sh"), work],
                   capture_output=True,
                   env=dict(os.environ, HYPRSIMPLE_PATH=repo, HOME=home))
    gen = os.path.join(work, "generated")
    files = {n: os.path.join(gen, n) for n in
             ("waybar-colors.css", "rofi-colors.rasi", "theme-clock.jsonc")}
    text = {}
    for n, path in files.items():
        if not os.path.isfile(path):
            bad.append(f"{name}: {n} was not rendered")
            continue
        text[n] = open(path).read()
        if "{{" in text[n]:
            bad.append(f"{name}: {n} left a placeholder unrendered")
    if len(text) < len(files):
        continue

    bar = dict(re.findall(r'@define-color ([a-z-]+) (#[0-9a-fA-F]{6})', text["waybar-colors.css"]))
    need = {"fg", "bg-widget", "bg-deep", "success", "warning", "danger", "info",
            "secondary", "accent", "accent-dim", "muted"}
    if not need <= set(bar):
        bad.append(f"{name}: waybar colours missing {sorted(need - set(bar))}")
        continue
    # Everything waybar draws sits on the widget surface.
    for key in ("fg", "success", "warning", "danger", "info", "secondary", "accent", "accent-dim"):
        c = contrast(bar[key], bar["bg-widget"])
        if c < 3.0:
            bad.append(f"{name}: waybar {key} {c:.1f}")
    # And the widget has to belong to the bar it sits on. Readability alone let
    # a pure black pill through on a pale theme.
    near = contrast(bar["bg-deep"], bar["bg-widget"])
    if near > 3.0:
        bad.append(f"{name}: widget {near:.1f} away from the bar behind it")

    menu = dict(re.findall(r'(\w[\w-]*):\s+(#[0-9a-fA-F]{6})', text["rofi-colors.rasi"]))
    need = {"background", "background-alt", "foreground", "selected", "active", "urgent", "muted"}
    if not need <= set(menu):
        bad.append(f"{name}: rofi colours missing {sorted(need - set(menu))}")
        continue
    for key, on in (("selected", "background-alt"), ("foreground", "background"),
                    ("active", "background"), ("urgent", "background")):
        c = contrast(menu[key], menu[on])
        if c < 3.0:
            bad.append(f"{name}: rofi {key} on {on} {c:.1f}")
    # Placeholder text is meant to be dim, not absent. It was landing at 1.0.
    c = contrast(menu["muted"], menu["background"])
    if c < 2.3:
        bad.append(f"{name}: rofi placeholder {c:.1f}")

    for colour in re.findall(r"color='(#[0-9a-fA-F]{6})'", text["theme-clock.jsonc"]):
        c = contrast(colour, bar["bg-deep"])
        if c < 3.0:
            bad.append(f"{name}: clock {colour} {c:.1f}")
print("; ".join(bad))
PYEOF
)
check "every interface colour is readable on what it is drawn on, on every theme" "$ui_report" ""

# The terminal palette is deliberately not in that check. colour0 to colour15
# stay exactly as each scheme publishes them, pale whites included: Solarized
# Light really does define its brightest white as its own background, and
# changing it would make this project's Solarized not Solarized.
untouched=$(python3 - "$THEMES" "$REPO" "$TMP" <<'PYEOF'
import os, re, sys
themes, repo, tmp = sys.argv[1], sys.argv[2], sys.argv[3]
bad = []
for name in sorted(os.listdir(themes)):
    d = os.path.join(themes, name)
    if name.startswith("templates") or not os.path.isdir(d):
        continue
    gen = os.path.join(tmp, "render", name, "generated", "ghostty.conf")
    if not os.path.isfile(gen):
        continue
    want = dict(re.findall(r'^color(\d+)\s*=\s*"(#[0-9A-Fa-f]{6})"\s*$',
                           open(os.path.join(d, "colors.toml")).read(), re.M))
    got = dict(re.findall(r'^palette\s*=\s*(\d+)=(#[0-9A-Fa-f]{6})\s*$', open(gen).read(), re.M))
    for slot, value in want.items():
        if slot in got and got[slot].lower() != value.lower():
            bad.append(f"{name}: colour{slot} {value} became {got[slot]}")
print("; ".join(bad))
PYEOF
)
check "and the terminal palette is passed through untouched" "$untouched" ""

# A colors.toml that does not define colour0, which a theme of your own may
# well not. The surface is computed from three keys, and without a fallback the
# substitution is empty and waybar is handed "@define-color bg-widget ;".
partial="$TMP/partial"
mkdir -p "$partial"
printf 'foreground = "#eeeeee"\nbackground = "#202020"\n' >"$partial/colors.toml"
HYPRSIMPLE_PATH="$REPO" HOME="$TMP/render-home" \
  "$BASH_BIN" "$REPO/.local/bin/theme-apply-templates.sh" "$partial" >/dev/null 2>&1
check "a theme missing colour0 still renders a colour for the widgets" \
  "$(grep -cE '^@define-color bg-widget #[0-9a-fA-F]{6};' "$partial/generated/waybar-colors.css")" "1"

# ---- the migration -------------------------------------------------------------

MBIN="$TMP/bin"; mkdir -p "$MBIN"
for tool in cat cp rm md5sum cut basename readlink find mkdir printf; do
  p=$(command -v "$tool" 2>/dev/null) && ln -sf "$p" "$MBIN/$tool"
done
cat >"$MBIN/systemctl" <<'STUBEOF'
#!/bin/bash
[[ ${SESSION_UP:-} == yes ]]
STUBEOF
chmod +x "$MBIN/systemctl"

make_home() {
  local h="$TMP/$1"; shift
  rm -rf "$h"
  mkdir -p "$h/.config/hypr/themes" "$h/.local/bin" "$h/.config/rofi"
  # A theme switcher that records rather than switches.
  cat >"$h/.local/bin/theme-switcher.sh" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SWITCH_LOG"
STUBEOF
  chmod +x "$h/.local/bin/theme-switcher.sh"
  for name in "$@"; do
    mkdir -p "$h/.config/hypr/themes/$name"
    [[ -f "$FIXTURES/$name.colors.toml" ]] &&
      cp "$FIXTURES/$name.colors.toml" "$h/.config/hypr/themes/$name/colors.toml"
  done
  printf '%s' "$h"
}
run_migration() {
  : >"$TMP/switches"
  HOME="$1" HYPRSIMPLE_PATH="$REPO" SESSION_UP="${SESSION_UP:-}" \
    SWITCH_LOG="$TMP/switches" PATH="$MBIN" \
    "$BASH_BIN" "$MIGRATION" >"$TMP/out" 2>&1
}
themes_in() {
  # find rather than ls, which SC2012 flags and which this project has shipped
  # a bug from before.
  find "$1/.config/hypr/themes" -mindepth 1 -maxdepth 1 -printf '%f\n' 2>/dev/null | sort | paste -sd' '
}

# An install as it was: the old themes, none of the new ones.
h=$(make_home old ethereal hackerman matte-black miasma osaka-jade ristretto vantablack white catppuccin)
run_migration "$h"
left=()
for n in ethereal hackerman matte-black miasma osaka-jade ristretto vantablack white; do
  [[ -e "$h/.config/hypr/themes/$n" ]] && left+=("$n")
done
check "the migration removes the omarchy themes" "${left[*]:-}" ""
check "and adds the new ones" \
  "$([[ -d $h/.config/hypr/themes/dracula && -d $h/.config/hypr/themes/solarized-light ]] && echo added || echo missing)" "added"
check "with their colours, wallpapers and icon theme" \
  "$([[ -f $h/.config/hypr/themes/dracula/colors.toml && -n $(find "$h/.config/hypr/themes/dracula/backgrounds" -type f -print -quit) && -f $h/.config/hypr/themes/dracula/icon-theme ]] && echo complete || echo incomplete)" \
  "complete"
check "and says how many it added and removed" \
  "$(grep -cE 'Added [0-9]+ theme|Removed [0-9]+ theme' "$TMP/out")" "2"

# A theme the user edited is theirs, and a theme of their own is left alone.
h=$(make_home edited miasma catppuccin)
printf 'accent = "#123456"\n' >"$h/.config/hypr/themes/miasma/colors.toml"
mkdir -p "$h/.config/hypr/themes/my-own"
printf 'mine\n' >"$h/.config/hypr/themes/my-own/colors.toml"
printf 'edited\n' >"$h/.config/hypr/themes/catppuccin/marker"
run_migration "$h"
check "an edited omarchy theme is kept" \
  "$([[ -d $h/.config/hypr/themes/miasma ]] && echo kept || echo removed)" "kept"
check "and named" "$(grep -c 'miasma' "$TMP/out")" "1"
check "a theme of your own is untouched" "$(cat "$h/.config/hypr/themes/my-own/colors.toml")" "mine"
check "and a shipped theme you already have is not overwritten" \
  "$([[ -f $h/.config/hypr/themes/catppuccin/marker ]] && echo untouched || echo replaced)" "untouched"
# The marker surviving is not enough on its own. `cp -r src dst` with dst
# already there copies into it, so a copy that should have been skipped leaves
# themes/catppuccin/catppuccin and every marker still in place.
nested=()
for d in "$h"/.config/hypr/themes/*/; do
  n=$(basename "$d")
  [[ -d "$d/$n" ]] && nested+=("$n")
done
check "and not copied inside itself" "${nested[*]:-}" ""

# Running it twice changes nothing more.
before=$(themes_in "$h")
run_migration "$h"
check "running it again changes nothing" "$(themes_in "$h")" "$before"
check "and adds or removes nothing the second time" \
  "$(grep -cE 'Added [0-9]+ theme|Removed [0-9]+ theme' "$TMP/out")" "0"
check "while still saying which theme it is leaving to you" "$(grep -c 'Left alone' "$TMP/out")" "1"

# The colour files are symlinks into the theme directory, so removing the theme
# in use without switching leaves every one of them dangling.
h=$(make_home active vantablack)
ln -sfn "$h/.config/hypr/themes/vantablack/generated/rofi-colors.rasi" "$h/.config/rofi/rofi-colors.rasi"
SESSION_UP=yes run_migration "$h"
check "removing the theme in use applies deep-sea" "$(cat "$TMP/switches")" "deep-sea"
check "and says why" "$(grep -c 'vantablack' "$TMP/out")" "1"

h=$(make_home active-tty vantablack)
ln -sfn "$h/.config/hypr/themes/vantablack/generated/rofi-colors.rasi" "$h/.config/rofi/rofi-colors.rasi"
SESSION_UP="" run_migration "$h"
check "from a TTY it still applies deep-sea, without reloading" "$(cat "$TMP/switches")" "deep-sea"

h=$(make_home inactive vantablack catppuccin)
ln -sfn "$h/.config/hypr/themes/catppuccin/generated/rofi-colors.rasi" "$h/.config/rofi/rofi-colors.rasi"
SESSION_UP=yes run_migration "$h"
check "removing a theme you are not using switches nothing" "$(wc -c <"$TMP/switches" | tr -d ' ')" "0"

mkdir -p "$TMP/bare"
run_migration "$TMP/bare"
check "a home with no themes directory is left alone" \
  "$([[ -e $TMP/bare/.config/hypr/themes ]] && echo created || echo absent)" "absent"

# ---- documented ---------------------------------------------------------------

check "the README counts the themes it ships" \
  "$(grep -c "\*\*${#names[@]} themes\*\*" "$REPO/README.md")" "1"

# ---- every theme has a wallpaper of its own -----------------------------------
#
# The catalogue arrived with one picture shared between the themes, a symlink to
# deep-sea's in each, until there was one for each. There is now.

shared=()
oversized=()
badname=()
for d in "$THEMES"/*/; do
  name=$(basename "$d")
  [[ $name == templates* ]] && continue
  while IFS= read -r wall; do
    base=$(basename "$wall")
    [[ -L $wall ]] && shared+=("$name/$base")
    (($(stat -c %s "$wall") > 2097152)) && oversized+=("$name/$base")
    [[ $base =~ ^[0-9]+-.+\.(jpg|jpeg|png|webp)$ ]] || badname+=("$name/$base")
  done < <(find "$d/backgrounds" -mindepth 1 -maxdepth 1)
done
check "no theme borrows another theme's wallpaper" "${shared[*]:-}" ""
# Everyone who installs hyprsimple clones these, so a 16 MiB png is everybody's
# download. The largest here is about 1 MiB.
check "no wallpaper is larger than 2 MiB" "${oversized[*]:-}" ""
check "every wallpaper is numbered and in a format the switchers read" "${badname[*]:-}" ""

# ---- the wallpaper migration ---------------------------------------------------

WALLPAPER_MIGRATION="$REPO/migrations/1789790910.sh"

run_wallpaper_migration() {
  : >"$TMP/switches"
  HOME="$1" HYPRSIMPLE_PATH="$REPO" SESSION_UP="${SESSION_UP:-}" \
    SWITCH_LOG="$TMP/switches" PATH="$MBIN" \
    "$BASH_BIN" "$WALLPAPER_MIGRATION" >"$TMP/wallout" 2>&1
}
# An install as the catalogue left it: the placeholder link and nothing else.
placeholder_home() {
  local h="$TMP/$1"
  rm -rf "$h"
  mkdir -p "$h/.local/bin" "$h/.config/rofi"
  cat >"$h/.local/bin/theme-switcher.sh" <<'STUBEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SWITCH_LOG"
STUBEOF
  chmod +x "$h/.local/bin/theme-switcher.sh"
  for name in dracula nord zenburn; do
    mkdir -p "$h/.config/hypr/themes/$name/backgrounds"
    ln -s "../../deep-sea/backgrounds/2-deep-sea.jpg" \
      "$h/.config/hypr/themes/$name/backgrounds/0-deep-sea.jpg"
  done
  printf '%s' "$h"
}

h=$(placeholder_home wallpaper-placeholder)
run_wallpaper_migration "$h"
check "the placeholder is replaced by the theme's own wallpaper" \
  "$([[ -e $h/.config/hypr/themes/dracula/backgrounds/0-deep-sea.jpg ]] && echo left || echo gone)" "gone"
check "and what arrives is the file hyprsimple ships" \
  "$(find "$h/.config/hypr/themes/dracula/backgrounds" -mindepth 1 -printf '%f\n' | paste -sd' ')" \
  "$(find "$THEMES/dracula/backgrounds" -mindepth 1 -printf '%f\n' | paste -sd' ')"
check "and it is a real file rather than another link" \
  "$(find "$h/.config/hypr/themes/dracula/backgrounds" -type f | wc -l)" "1"
check "and it says how many themes it reached" \
  "$(grep -cE '3 theme\(s\) now have their own wallpaper' "$TMP/wallout")" "1"

snapshot=$(find "$h/.config/hypr/themes" -mindepth 1 -printf '%P\n' | sort | paste -sd' ')
run_wallpaper_migration "$h"
check "running it again changes nothing" \
  "$(find "$h/.config/hypr/themes" -mindepth 1 -printf '%P\n' | sort | paste -sd' ')" "$snapshot"
check "and says every theme has its own already" \
  "$(grep -c 'already has its own wallpaper' "$TMP/wallout")" "1"

# A picture of your own in there, beside the link or instead of it, means the
# directory is yours.
h=$(placeholder_home wallpaper-yours)
printf 'mine\n' >"$h/.config/hypr/themes/nord/backgrounds/1-mine.jpg"
rm "$h/.config/hypr/themes/zenburn/backgrounds/0-deep-sea.jpg"
printf 'mine\n' >"$h/.config/hypr/themes/zenburn/backgrounds/0-mine.jpg"
run_wallpaper_migration "$h"
check "a wallpaper added beside the placeholder keeps the directory yours" \
  "$(find "$h/.config/hypr/themes/nord/backgrounds" -mindepth 1 -printf '%f\n' | sort | paste -sd' ')" \
  "0-deep-sea.jpg 1-mine.jpg"
check "and a directory with your own wallpaper in it is left alone" \
  "$(find "$h/.config/hypr/themes/zenburn/backgrounds" -mindepth 1 -printf '%f\n' | paste -sd' ')" \
  "0-mine.jpg"
check "so only the untouched theme is changed" \
  "$(grep -cE '1 theme\(s\) now have' "$TMP/wallout")" "1"

# The wallpaper on screen is a copy in ~/.cache, so the theme in use has to be
# applied again or it keeps showing deep-sea.
h=$(placeholder_home wallpaper-active)
ln -sf "$h/.config/hypr/themes/nord/generated/rofi-colors.rasi" "$h/.config/rofi/rofi-colors.rasi"
SESSION_UP=yes run_wallpaper_migration "$h"
check "the theme in use is applied again so the new wallpaper shows" \
  "$(cat "$TMP/switches")" "nord"
check "and it says so" "$(grep -c 'nord is the theme in use' "$TMP/wallout")" "1"

h=$(placeholder_home wallpaper-nothemes)
rm -rf "$h/.config/hypr/themes"
run_wallpaper_migration "$h"
check "a home with no themes directory is left alone" \
  "$(grep -c 'nothing to change' "$TMP/wallout")" "1"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
