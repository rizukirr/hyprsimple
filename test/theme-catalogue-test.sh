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
        elif os.path.isdir("/usr/share/icons") and not os.path.isdir(f"/usr/share/icons/{icon}"):
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
  "$([[ -f $h/.config/hypr/themes/dracula/colors.toml && -e $h/.config/hypr/themes/dracula/backgrounds/0-deep-sea.jpg && -f $h/.config/hypr/themes/dracula/icon-theme ]] && echo complete || echo incomplete)" \
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

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
