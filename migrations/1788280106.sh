echo "Render the new wlogout colours for the themes you already have"

# The migration that themed wlogout installed the shipped fallback and updated
# style.css, but nothing rendered the new template, so every existing install
# sat on the fallback's catppuccin colours until its next theme switch. The
# template is a new build input, and a build input that is never built reaches
# nobody. 1788069834.sh had the same shape and re-rendered for the same reason.

THEMES="$HOME/.config/hypr/themes"
RENDER="$HOME/.local/bin/theme-apply-templates.sh"
[[ -d $THEMES && -x $RENDER ]] || exit 0
[[ -f $HYPRSIMPLE_PATH/.config/hypr/themes/templates/wlogout-colors.css.tpl ]] || exit 0

# Idempotent: rendering is deterministic from colors.toml, so a re-run writes
# the same bytes. Only themes that can be rendered at all are touched.
rendered=0
for dir in "$THEMES"/*/; do
  name=$(basename "$dir")
  [[ $name == templates || $name == templates.user ]] && continue
  [[ -f $dir/colors.toml ]] || continue
  "$RENDER" "$dir" >/dev/null 2>&1 && rendered=$((rendered + 1))
done
echo "Rendered templates for $rendered theme(s)"

# Then put the active theme's colours where wlogout reads them. theme-active.lua
# points into the active theme's generated directory, which is the same place
# theme-switcher.sh copies from.
active=$(readlink "$HOME/.config/hypr/theme-active.lua" 2>/dev/null)
if [[ -n $active && -f ${active%/*}/wlogout-colors.css ]]; then
  mkdir -p "$HOME/.config/wlogout"
  cp "${active%/*}/wlogout-colors.css" "$HOME/.config/wlogout/wlogout-colors.css"
  echo "wlogout now uses your active theme's colours"
fi
