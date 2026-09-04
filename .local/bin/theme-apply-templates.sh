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
