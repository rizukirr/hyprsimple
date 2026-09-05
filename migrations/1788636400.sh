echo "Point btop at the theme hyprsimple has been generating for it"

# hyprsimple installs btop, install.sh creates ~/.config/btop/themes, every
# shipped theme renders a btop.theme, and every theme switch copied one to
# themes/current.theme. Nothing ever told btop to use it: btop.conf still said
# color_theme = "Default", which is what btop writes for itself on first run.
# The themed btop has never worked on any install.
#
# Only a config that has not chosen a theme is changed. "Default" and "TTY" are
# btop's two built-ins, and a missing key means the same thing. Anything else is
# a theme the user picked, and is left alone.

CONF="$HOME/.config/btop/btop.conf"
THEME="$HOME/.config/btop/themes/current.theme"

if [[ ! -f $THEME ]]; then
  echo "  No generated btop theme here yet. Switching theme will write one."
  exit 0
fi

if [[ ! -f $CONF ]]; then
  mkdir -p "$(dirname "$CONF")"
  printf 'color_theme = "current"\n' >"$CONF"
  echo "  Created $CONF selecting the generated theme."
  exit 0
fi

current=$(sed -n 's/^color_theme = "\(.*\)"$/\1/p' "$CONF" | head -1)

case "$current" in
  current)
    exit 0
    ;;
  "" | Default | TTY)
    cp -f "$CONF" "$CONF.bak"
    if grep -q '^color_theme = ' "$CONF"; then
      sed -i 's|^color_theme = .*|color_theme = "current"|' "$CONF"
    else
      printf 'color_theme = "current"\n' >>"$CONF"
    fi
    echo "  btop now uses your hyprsimple theme (previous config at $CONF.bak)."
    ;;
  *)
    echo "  btop is set to the \"$current\" theme, which you chose, so it was left alone."
    echo "  To use hyprsimple's instead, set this in $CONF:"
    echo "    color_theme = \"current\""
    ;;
esac
