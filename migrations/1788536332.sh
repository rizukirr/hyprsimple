echo "Repair the power menu's logout and suspend actions"

# The rofi power menu was adapted from a widely copied one written for other
# window managers, and two of its actions never worked here.
#
# Logout branched on $DESKTOP_SESSION for openbox, bspwm, i3 and plasma, with no
# other branch. $DESKTOP_SESSION is hyprland-uwsm, so confirming a logout ran
# nothing at all.
#
# Suspend ran `mpc -q pause` and `amixer set Master mute` first. mpc is not
# installed and is in no package list. The mute worked, and nothing undid it, so
# suspending from the menu left the machine silent after resume.
#
# powermenu.sh lives in ~/.config and is never overwritten by an update, so
# without this the fix reaches nobody who already has hyprsimple installed.
# A copy byte-identical to something this project shipped was never edited and
# is replaced. Anything else is left alone and the command to update it printed.

user="$HOME/.config/rofi/powermenu/powermenu.sh"
shipped="$HYPRSIMPLE_PATH/.config/rofi/powermenu/powermenu.sh"

[[ -f $user && -f $shipped ]] || exit 0

# Already current, which is what makes a re-run a no-op.
cmp -s "$user" "$shipped" && exit 0

# Every version of this file the project shipped before the current one.
SHIPPED_SUMS=(
  3a13e65338adacb0b9e4e40439d9fd29
  60bb292cbeeef718f399e62d85df0270
  6baf25fda5829db4a7dd69ee6d723c41
  9d1dabc852a8eefe4dfb4824515ee9a7
  d735bfeed77cc80069573b3b2fdc3c3d
  dea28bfea098a3010931f3799874b4a9
  f84d2caf5815068ed99efeeb5222a548
  fe76f1deb8f92579f1f2e66aa5304861
)

sum=$(md5sum "$user" | cut -d' ' -f1)

for known in "${SHIPPED_SUMS[@]}"; do
  if [[ $sum == "$known" ]]; then
    cp -f "$user" "$user.bak"
    cp -f "$shipped" "$user"
    echo "  Updated $user (previous version kept at $user.bak)"
    echo "  Logout now logs out, and suspend no longer mutes your audio."
    exit 0
  fi
done

echo "  $user has your own edits, so it was left alone."
echo "  Its logout does nothing under Hyprland and its suspend mutes your audio."
echo "  To take hyprsimple's version and lose your edits:"
echo "    hyprsimple-refresh-config.sh rofi/powermenu/powermenu.sh"
