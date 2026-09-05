echo "Keep one broken override from taking the whole config down"

# ~/.config/hypr/hyprland.lua required your six override files with a bare
# require. A syntax error in any of them, or a deleted one, aborted the file:
# every later require and the theme overlay at the bottom never ran, so the
# session came up with no theme, no bindings from the later files, and nothing
# saying why. Measured with a one-character typo in windows.lua.
#
# default/hypr/vars.lua already loaded your vars.lua with pcall for exactly this
# reason. The entrypoint now does the same and names the file that failed.
#
# hyprland.lua is yours, so it is only replaced when it is still byte-identical
# to a version hyprsimple shipped. An edited one is left alone and reported.

user="$HOME/.config/hypr/hyprland.lua"
shipped="$HYPRSIMPLE_PATH/.config/hypr/hyprland.lua"

[[ -f $user && -f $shipped ]] || exit 0

if cmp -s "$user" "$shipped"; then
  exit 0
fi

# Every version of this file the project shipped before the current one.
SHIPPED_SUMS=(
  0c1d78c21b6dc7bf6d1c73a3403fd3dd
  75f67c42753b28e5a9189b8a65009e27
  af26427696efda1879c6fba8a355cb50
)

sum=$(md5sum "$user" | cut -d' ' -f1)

for known in "${SHIPPED_SUMS[@]}"; do
  if [[ $sum == "$known" ]]; then
    cp -f "$user" "$user.bak"
    cp -f "$shipped" "$user"
    echo "  Updated $user (previous version kept at $user.bak)"
    echo "  A broken override file now reports itself instead of silently"
    echo "  taking the rest of your config with it."
    exit 0
  fi
done

echo "  $user has your own edits, so it was left alone."
echo "  It still loads your override files with a bare require, so a syntax"
echo "  error in any of them takes down everything after it."
echo "  To take hyprsimple's version and lose your edits:"
echo "    hyprsimple-refresh-config.sh hypr/hyprland.lua"
