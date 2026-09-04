echo "Remove generated theme files whose template no longer exists"

# Rendering only ever wrote. When a template was removed, its output stayed in
# every theme forever: dropping the wlogout power menu left wlogout-colors.css
# in all sixteen. theme-apply-templates.sh now removes an output with no
# template behind it, but the re-render on update is gated on the template
# contents changing, and they do not change here. So this runs it once.
#
# Nothing is deleted directly. The renderer decides, which means this migration
# cannot disagree with the rule it is delivering.

RENDERER="$HOME/.local/bin/theme-apply-templates.sh"
THEMES="$HOME/.config/hypr/themes"

[[ -x $RENDERER && -d $THEMES ]] || exit 0

# Counting names that disappeared, not the change in how many files there are.
# A render can add a file in the same pass that it removes one, and then the
# difference in counts is zero while something really was deleted.
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

cleaned=0
for dir in "$THEMES"/*/; do
  name=$(basename "$dir")
  [[ $name == templates || $name == templates.user ]] && continue
  [[ -f $dir/colors.toml ]] || continue
  find "$dir/generated" -type f -printf '%f\n' 2>/dev/null | sort >"$work/before"
  "$RENDERER" "$dir" >/dev/null 2>&1 || continue
  find "$dir/generated" -type f -printf '%f\n' 2>/dev/null | sort >"$work/after"
  gone=$(comm -23 "$work/before" "$work/after" | grep -c . || true)
  cleaned=$((cleaned + gone))
done

if (( cleaned > 0 )); then
  echo "  Removed $cleaned stale file(s) from your themes"
fi
