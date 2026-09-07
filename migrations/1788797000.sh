echo "Correct a GTK theme name written from a session that could not be read"

# Migration 1788793000 wrote ~/.config/gtk-{3,4}.0/settings.ini from
#
#   gsettings get org.gnome.desktop.interface gtk-theme
#
# and gsettings does not fail without a session bus: it answers with the schema
# default. Run from a TTY, which is what bootstrap.sh is for, that returns
# 'Adwaita' on a machine whose theme is Adwaita-dark. Measured by running
# bootstrap.sh under env -i against a fresh HOME.
#
# So machines bootstrapped from a console got a light theme name written for a
# dark desktop, and because the file then existed nothing corrected it.
# 1788793000 reads light.mode now, but it has already run on those machines.
#
# Only the exact file that migration writes is touched: two lines, a [Settings]
# header and the key, and nothing else. Anything a person has edited since has
# more in it than that and is left alone.

want=""
active_lua=$(readlink "$HOME/.config/hypr/theme-active.lua" 2>/dev/null)
if [[ -n $active_lua ]]; then
  theme_dir=$(dirname "$(dirname "$active_lua")")
  if [[ -d $theme_dir ]]; then
    if [[ -f $theme_dir/light.mode ]]; then want="Adwaita"; else want="Adwaita-dark"; fi
  fi
fi

if [[ -z $want ]]; then
  echo "  Could not tell which theme is active, so nothing was changed."
  exit 0
fi

corrected=0
for gtk_dir in "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"; do
  settings="$gtk_dir/settings.ini"
  [[ -f $settings ]] || continue

  # Exactly the shape 1788793000 writes, and no more.
  [[ $(wc -l <"$settings") -eq 2 ]] || continue
  [[ $(sed -n '1p' "$settings") == "[Settings]" ]] || continue

  current=$(sed -n '2p' "$settings")
  [[ $current == gtk-theme-name=* ]] || continue
  [[ $current == "gtk-theme-name=$want" ]] && continue

  printf '[Settings]\ngtk-theme-name=%s\n' "$want" >"$settings"
  corrected=$((corrected + 1))
done

if (( corrected > 0 )); then
  echo "  Corrected $corrected settings.ini to $want, matching the theme you have."
else
  echo "  Nothing to correct."
fi
