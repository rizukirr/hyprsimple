echo "Update the application keybindings to match the programs hyprsimple installs"

# #62 removed SUPER + O, SUPER + S and SUPER + E, and removed M.notes and
# M.androidstudio from default/hypr/vars.lua with them. vars.lua is install
# owned and arrived on the next update. ~/.config/hypr/bindings/applications.lua
# is user owned and did not, so an existing install was left with a bindings
# file reading two keys that no longer existed. exec_cmd raised "expected
# string, got nil" and the whole config was rejected, not just those two lines.
#
# vars.lua now answers an unknown key with a command that explains itself, so
# nothing crashes either way. This migration is the tidier half: a bindings file
# that is byte-identical to something this project shipped was never edited, so
# it is replaced outright and the three dead keys go away instead of turning
# into a notification. Anything else is left alone and the command to update it
# is printed instead.

user="$HOME/.config/hypr/bindings/applications.lua"
shipped="$HYPRSIMPLE_PATH/.config/hypr/bindings/applications.lua"

[[ -f $user && -f $shipped ]] || exit 0

# Already current, which is what makes a re-run a no-op.
cmp -s "$user" "$shipped" && exit 0

# Every version of this file the project has shipped before the current one,
# from git history.
SHIPPED_SUMS=(
  1122945c51f39e1bc3d832e8209817d1
  415fd3c8498075c259e2e88040b93c3a
)

sum=$(md5sum "$user" | cut -d' ' -f1)

for known in "${SHIPPED_SUMS[@]}"; do
  if [[ $sum == "$known" ]]; then
    cp -f "$user" "$user.bak"
    cp -f "$shipped" "$user"
    echo "  Updated $user (previous version kept at $user.bak)"
    exit 0
  fi
done

echo "  $user has your own edits, so it was left alone."
echo "  SUPER + O, SUPER + S and SUPER + E now report that they are unset."
echo "  To take hyprsimple's version and lose your edits:"
echo "    hyprsimple-refresh-config.sh hypr/bindings/applications.lua"
