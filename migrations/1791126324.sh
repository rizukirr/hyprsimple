echo "Move notifications from dunst to the bar"

# The bar shows the notifications now: they grow out of its top right corner,
# and its bell opens a sidebar with the ones that have been. dunst is no longer
# started at login or installed, and its config, colour template and restart
# script are gone from the install.
#
# An install from before that still has dunst running in this session, holding
# the name notifications are sent to, so the bar cannot take it. And it still
# has the dunst package, which D-Bus starts by itself whenever a notification
# is sent while nothing else holds that name, which is every time the bar
# restarts. Once started it keeps the name.
#
# This stops dunst, removes the two files hyprsimple put under ~/.config/dunst,
# and removes the package. ~/.config/dunst/dunstrc is yours and is left where
# it is. Nothing reads it any more.

# Checked before anything is stopped. The update carries on when a package
# fails to install, so quickshell can be missing here, and taking dunst away
# as well would leave no notifications at all. Failing leaves dunst running and
# runs this again on the next update.
if ! command -v qs >/dev/null 2>&1; then
  echo "quickshell is not installed, so dunst is left as it is." >&2
  echo "Install it with: sudo pacman -S quickshell ttf-material-symbols-variable" >&2
  echo "Then run hyprsimple-migrate." >&2
  exit 1
fi

# The bar takes the name by itself as soon as dunst lets go of it.
if pgrep -x dunst >/dev/null; then
  pkill -x dunst
  echo "  Stopped dunst."
fi

# The link into the install, which dangles now, and the theme's colours, which
# hyprsimple wrote and nothing rewrites any more.
for ours in "$HOME/.config/dunst/dunstrc.d/10-hyprsimple.conf" \
  "$HOME/.config/dunst/dunstrc.d/90-theme.conf"; do
  if [[ -e $ours || -L $ours ]]; then
    rm -f "$ours"
    echo "  Removed $ours"
  fi
done

# hyprsimple-restart-dunst.sh is left in ~/.local/bin. The update running this
# migration is the one from before the change, still being read from its old
# copy, and it may call that script afterwards. Left in place it does nothing:
# it is called with --if-running and dunst is no longer running.

# A binding or script of your own may call dunstctl, or start dunst. Those
# files are yours and are not rewritten, so when one is found the package is
# left installed and the files are named.
mine=()
if [[ -d $HOME/.config/hypr ]]; then
  while IFS= read -r file; do
    mine+=("$file")
  done < <(grep -rlE --include='*.lua' --include='*.conf' --include='*.sh' \
    '(^|[^a-zA-Z_-])(dunst|dunstctl|dunstify)([^a-zA-Z_-]|$)' "$HOME/.config/hypr" 2>/dev/null)
fi

if ((${#mine[@]} > 0)); then
  echo "  These files of yours still call dunst, so the dunst package is left installed:"
  printf '    %s\n' "${mine[@]}"
  echo "  While it is installed, D-Bus starts dunst whenever the bar restarts, and"
  echo "  the bar's notifications stop until dunst is stopped again."
  exit 0
fi

# Asked for only when there is something to remove, so a machine without dunst
# never reaches sudo. A removal that fails, or one pacman refuses because
# another package needs dunst, is reported and does not stop the update.
if pacman -Qi dunst >/dev/null 2>&1; then
  if sudo pacman -Rs --noconfirm dunst >/dev/null 2>&1; then
    echo "  Removed the dunst package."
  else
    echo "  Could not remove the dunst package. Remove it with: sudo pacman -Rs dunst"
  fi
fi

exit 0
