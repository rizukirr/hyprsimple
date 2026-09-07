echo "Write the GTK settings.ini that theme switches never created"

# theme-switcher.sh has always ended with
#
#   mkdir -p "$gtk_dir"
#   [[ -f "$gtk_dir/settings.ini" ]] && sed -i "s/^gtk-theme-name=.*/.../"
#
# under a comment saying some apps read these instead of gsettings. Nothing in
# hyprsimple has ever created settings.ini, so the mkdir made the directory,
# the test then failed, and the block wrote nothing on every theme switch.
# Measured on a live install that had switched themes many times:
# ~/.config/gtk-3.0 and ~/.config/gtk-4.0 both present and both empty.
#
# theme-switcher.sh writes the file now, but only when a theme is next
# switched, which may be never. This writes it once from the theme already in
# force, so the apps that read it stop disagreeing with the rest of the desktop.
#
# Only when the file is absent. A settings.ini that exists is the user's, and
# the next theme switch edits just the one key in it.

# The theme is derived from hyprsimple's own state, not from gsettings.
#
# gsettings does not fail without a session bus: it answers with the schema
# default. Run from a TTY, which is what bootstrap.sh is for, `gsettings get
# org.gnome.desktop.interface gtk-theme` returns 'Adwaita' on a machine whose
# theme is Adwaita-dark. Measured by running bootstrap.sh under env -i against
# a fresh HOME. So this wrote a light theme name for a dark desktop, and
# because the file then exists it was never corrected.
#
# light.mode is the same thing theme-switcher.sh reads to make this decision,
# it lives in the theme directory, and it needs no session at all.
wrote=0

active_lua=$(readlink "$HOME/.config/hypr/theme-active.lua" 2>/dev/null)
theme=""
if [[ -n $active_lua ]]; then
  # .../themes/<name>/generated/hyprland-colors.lua
  theme_dir=$(dirname "$(dirname "$active_lua")")
  if [[ -d $theme_dir ]]; then
    if [[ -f $theme_dir/light.mode ]]; then theme="Adwaita"; else theme="Adwaita-dark"; fi
  fi
fi

if [[ -z $theme ]]; then
  echo "  Could not tell which theme is active, so nothing was written."
  echo "  Your next theme switch writes these files."
  exit 0
fi

for gtk_dir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
  settings="$gtk_dir/settings.ini"
  [[ -e $settings ]] && continue
  mkdir -p "$gtk_dir"
  printf '[Settings]\ngtk-theme-name=%s\n' "$theme" >"$settings"
  wrote=$((wrote + 1))
done

if (( wrote > 0 )); then
  echo "  Wrote $wrote settings.ini naming $theme. Your next theme switch keeps them in step."
else
  echo "  Both settings.ini files already exist, so they were left alone."
fi
