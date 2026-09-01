echo "Make the wlogout power menu follow the active theme"

# wlogout's colours were hardcoded catppuccin, so the power menu stayed
# catppuccin whatever theme was active. style.css now imports
# wlogout-colors.css, which a theme switch rewrites from the theme's
# colors.toml.
#
# Order matters here. GTK treats a missing @import as a fatal parse error and
# returns an empty stylesheet, so style.css must never be replaced before the
# file it imports exists, or the power menu renders completely unstyled until
# the next theme switch.

WL="$HOME/.config/wlogout"
[[ -d $WL ]] || exit 0

SHIPPED_STYLE="$HYPRSIMPLE_PATH/.config/wlogout/style.css"
SHIPPED_COLORS="$HYPRSIMPLE_PATH/.config/wlogout/wlogout-colors.css"
[[ -f $SHIPPED_STYLE && -f $SHIPPED_COLORS ]] || exit 0

# Every version of style.css this project has shipped before the import was
# added. A copy matching one of these was never edited.
STYLE_SUMS=(
  23c98a2fd7995835b53e3a03bfa3c5cf
  d755cc157e17e63dc8aa1b4f091d4517
)

# 1. The imported file first, always. Idempotent: rendering it again from the
#    active theme is what the next theme switch would do anyway.
if [[ ! -f $WL/wlogout-colors.css ]]; then
  cp "$SHIPPED_COLORS" "$WL/wlogout-colors.css"
  echo "Installed $WL/wlogout-colors.css"
fi

active=$(readlink "$HOME/.config/hypr/theme-active.lua" 2>/dev/null)
if [[ -n $active ]]; then
  gen="${active%/*}"
  if [[ -f $gen/wlogout-colors.css ]]; then
    cp "$gen/wlogout-colors.css" "$WL/wlogout-colors.css"
    echo "Applied the active theme's colours to wlogout"
  fi
fi

# 2. Only then the stylesheet that imports it.
if cmp -s "$WL/style.css" "$SHIPPED_STYLE"; then
  exit 0
fi

sum=$(md5sum "$WL/style.css" | cut -d' ' -f1)
for s in "${STYLE_SUMS[@]}"; do
  if [[ $sum == "$s" ]]; then
    cp "$SHIPPED_STYLE" "$WL/style.css"
    echo "Updated $WL/style.css"
    exit 0
  fi
done

echo ""
echo "$WL/style.css has your own edits, so it was left alone."
echo "It still uses hardcoded colours. To follow the theme, add this line at"
echo "the top and replace the colour literals with @wl_background and"
echo "@wl_foreground:"
echo ""
echo "    @import url(\"wlogout-colors.css\");"
echo ""
echo "Or take hyprsimple's version, keeping a backup of yours:"
echo ""
echo "    hyprsimple-refresh-config.sh wlogout/style.css"
echo ""
