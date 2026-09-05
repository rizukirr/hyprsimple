echo "Give vantablack an icon theme that exists"

# vantablack named Yaru-gray. Yaru has no gray: the variants it ships are
# Yaru and Yaru-bark, -blue, -dark, -magenta, -mate, -olive, -prussiangreen,
# -purple, -red, -sage, -viridian, -wartybrown, -yellow. Selecting vantablack
# therefore set gsettings icon-theme to a name nothing provides and GTK fell
# back to hicolor.
#
# #91 corrected the shipped file to Yaru-dark and stopped there. Everything
# under ~/.config is copied once and never overwritten, so that correction
# reached new installs only, and every machine installed before #91 still
# names the theme that does not exist. This carries it the rest of the way.
#
# Only the exact wrong value is replaced. Anything else in this file is a
# choice someone made and is left alone.

THEME_FILE="$HOME/.config/hypr/themes/vantablack/icons.theme"

if [[ ! -f $THEME_FILE ]]; then
  echo "  No vantablack theme here, nothing to do."
  exit 0
fi

current=$(tr -d '[:space:]' <"$THEME_FILE")

case "$current" in
  Yaru-dark)
    exit 0
    ;;
  Yaru-gray)
    printf 'Yaru-dark\n' >"$THEME_FILE"
    echo "  vantablack now uses Yaru-dark. Yaru-gray does not exist."
    ;;
  *)
    echo "  vantablack names the \"$current\" icon theme, which you chose, so it was left alone."
    exit 0
    ;;
esac

# Rewriting the file is enough for the next theme switch, but if vantablack is
# the theme in force right now then gsettings still holds Yaru-gray, and
# nothing would correct it until the user switched away and back.
#
# readlink exits non-zero when the path is not a symlink, which is an ordinary
# state here rather than an error.
active_lua=$(readlink "$HOME/.config/hypr/theme-active.lua" 2>/dev/null || true)
active_theme=""
if [[ -n $active_lua ]]; then
  # .../themes/<name>/generated/hyprland-colors.lua
  active_theme=$(basename "$(dirname "$(dirname "$active_lua")")")
fi

if [[ $active_theme == vantablack ]] && command -v gsettings >/dev/null 2>&1; then
  gsettings set org.gnome.desktop.interface icon-theme Yaru-dark 2>/dev/null || true
  echo "  vantablack is active, so the change was applied now rather than at the next switch."
fi
