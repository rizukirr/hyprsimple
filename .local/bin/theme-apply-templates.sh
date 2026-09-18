#!/bin/bash

# Usage: theme-apply-templates.sh <theme-dir>
# Reads colors.toml from theme dir, processes templates, outputs generated configs

THEME_DIR="$1"
# Templates are build inputs, not config, so the install owns them and a change
# to one reaches every user through hyprsimple-update alone. No migration.
#
# The install always wins over ~/.config/hypr/themes/templates. install.sh
# copied every template into every existing home, and a stale copy cannot be
# told apart from a customised one by comparing it to the current shipped file:
# both simply differ. Honouring the home directory would therefore leave every
# existing install pinned to the templates it was installed with, which is the
# gap this closes.
#
# An override lives in templates.user/ instead, where its presence is a
# deliberate act rather than a leftover.
TEMPLATES_DIR="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/.config/hypr/themes/templates"
USER_TEMPLATES_DIR="$HOME/.config/hypr/themes/templates.user"
STALE_TEMPLATES_DIR="$HOME/.config/hypr/themes/templates"

# Resolve one template name to the file to render.
template_path() {
  local name="$1"
  [[ -f $USER_TEMPLATES_DIR/$name ]] && { printf '%s' "$USER_TEMPLATES_DIR/$name"; return 0; }
  [[ -f $TEMPLATES_DIR/$name ]] && printf '%s' "$TEMPLATES_DIR/$name"
}

# A home template that differs from the shipped one was probably edited on
# purpose, and is now being ignored. Say so rather than change the result
# silently. Identical leftovers are not worth mentioning.
warn_about_stale() {
  local name="$1" stale="$STALE_TEMPLATES_DIR/$1"
  [[ -f $stale && -f $TEMPLATES_DIR/$name ]] || return 0
  cmp -s "$stale" "$TEMPLATES_DIR/$name" && return 0
  [[ -f $USER_TEMPLATES_DIR/$name ]] && return 0
  echo "Note: $stale differs from hyprsimple's and is no longer used." >&2
  echo "      Move it to $USER_TEMPLATES_DIR/ to keep it." >&2
}
COLORS_FILE="$THEME_DIR/colors.toml"

if [[ ! -f $COLORS_FILE ]]; then
  echo "No colors.toml found in $THEME_DIR, skipping template generation"
  exit 0
fi

# Convert hex color to decimal RGB (e.g., "#1e1e2e" -> "30,30,46")
hex_to_rgb() {
  local hex="${1#\#}"
  printf "%d,%d,%d" "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}"
}

# Build sed script from colors.toml
sed_script=$(mktemp)

while IFS='=' read -r key value; do
  key="${key//[\"\' ]/}"
  [[ $key && $key != \#* ]] || continue
  value="${value#*[\"\']}"
  value="${value%%[\"\']*}"

  printf 's|{{ %s }}|%s|g\n' "$key" "$value"
  printf 's|{{ %s_strip }}|%s|g\n' "$key" "${value#\#}"
  if [[ $value =~ ^# ]]; then
    rgb=$(hex_to_rgb "$value")
    echo "s|{{ ${key}_rgb }}|${rgb}|g"
  fi
done <"$COLORS_FILE" >"$sed_script"

# A surface to sit text on, for the widget pills in waybar.
#
# Those used colour0 directly, which is the terminal's black. On a dark theme
# that is a near-black behind light text and reads fine. On a light theme it is
# still black, while the text is dark, so the waybar text was unreadable:
# measured across the shipped themes, seven light ones and material-ocean fell
# below 3:1, catppuccin-latte at 1.3 and flexoki-light at 1.0, which is text and
# background the same colour.
#
# Computed rather than written into every colors.toml, so a theme of your own
# gets a readable bar without having to know the key exists.
surface_for() {
  awk -v fg="$1" -v bg="$2" -v c0="$3" '
    function chan(h,   v) {
      v = strtonum("0x" h) / 255
      return (v <= 0.04045) ? v / 12.92 : ((v + 0.055) / 1.055) ^ 2.4
    }
    function lum(hex) {
      return 0.2126 * chan(substr(hex, 2, 2)) + 0.7152 * chan(substr(hex, 4, 2)) + 0.0722 * chan(substr(hex, 6, 2))
    }
    function contrast(a, b,   la, lb, t) {
      la = lum(a); lb = lum(b)
      if (la < lb) { t = la; la = lb; lb = t }
      return (la + 0.05) / (lb + 0.05)
    }
    function part(hex, i,   v) { return strtonum("0x" substr(hex, i, 2)) }
    function mix(a, b, amt,   r, g, bl) {
      r  = part(a, 2) + (part(b, 2) - part(a, 2)) * amt
      g  = part(a, 4) + (part(b, 4) - part(a, 4)) * amt
      bl = part(a, 6) + (part(b, 6) - part(a, 6)) * amt
      return sprintf("#%02x%02x%02x", int(r + 0.5), int(g + 0.5), int(bl + 0.5))
    }
    BEGIN {
      # The theme own colour0 where it is readable and sits near the theme
      # background, so dark themes look exactly as they did. Readability alone
      # is not enough: ayu-light pairs dark grey text with a pure black
      # colour0, which clears 3:1 and still puts a black pill on a pale bar.
      if (contrast(fg, c0) >= 3.0 && contrast(bg, c0) <= 3.0) { print c0; exit }
      # Otherwise a shade of the background, lifted towards the text. That
      # stays the theme own colour and works the same way on light and dark.
      print mix(bg, fg, 0.12)
    }'
}

fg_value=$(sed -n 's/^foreground[[:space:]]*=[[:space:]]*"\(#[0-9A-Fa-f]\{6\}\)".*/\1/p' "$COLORS_FILE" | head -1)
bg_value=$(sed -n 's/^background[[:space:]]*=[[:space:]]*"\(#[0-9A-Fa-f]\{6\}\)".*/\1/p' "$COLORS_FILE" | head -1)
c0_value=$(sed -n 's/^color0[[:space:]]*=[[:space:]]*"\(#[0-9A-Fa-f]\{6\}\)".*/\1/p' "$COLORS_FILE" | head -1)

if [[ -n $fg_value && -n $bg_value && -n $c0_value ]]; then
  surface=$(surface_for "$fg_value" "$bg_value" "$c0_value")
else
  # A colors.toml missing one of the three gets the old behaviour rather than
  # an empty substitution, which would leave {{ surface }} in the output.
  surface="${c0_value:-${bg_value:-#000000}}"
fi

{
  printf 's|{{ surface }}|%s|g\n' "$surface"
  printf 's|{{ surface_strip }}|%s|g\n' "${surface#\#}"
  printf 's|{{ surface_rgb }}|%s|g\n' "$(hex_to_rgb "$surface")"
} >>"$sed_script"

# Generate configs from templates
mkdir -p "$THEME_DIR/generated"

# The union of the install and the override directory, so a template added to
# the repository renders without the user having anything at all.
rendered=()
while IFS= read -r name; do
  warn_about_stale "$name"
  tpl=$(template_path "$name")
  [[ -n $tpl ]] || continue
  sed -f "$sed_script" "$tpl" >"$THEME_DIR/generated/${name%.tpl}"
  rendered+=("${name%.tpl}")
done < <(
  {
    # Globs rather than `ls | grep`, which splits a template name containing a
    # space into two names and then renders neither.
    for f in "$TEMPLATES_DIR"/*.tpl "$USER_TEMPLATES_DIR"/*.tpl; do
      [[ -f $f ]] && basename "$f"
    done
  } | sort -u
)

# Everything under generated/ is written by this script and read by nothing
# else, so a file here with no template behind it is output from a template
# that has since been removed. wlogout's colours sat in all sixteen themes
# after the power menu was dropped, because rendering only ever wrote.
#
# Guarded on having rendered something. If TEMPLATES_DIR were missing or empty
# the loop above would produce no names, and reconciling against an empty set
# would delete every generated file in every theme.
if (( ${#rendered[@]} > 0 )); then
  for existing in "$THEME_DIR/generated"/*; do
    [[ -f $existing ]] || continue
    keep=0
    for name in "${rendered[@]}"; do
      [[ $(basename "$existing") == "$name" ]] && keep=1 && break
    done
    (( keep )) || rm -f "$existing"
  done
fi

rm "$sed_script"
echo "Templates generated in $THEME_DIR/generated/"
