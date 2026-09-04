#!/usr/bin/env bash

# The rofi power menu, bound to SUPER + ESCAPE and to the waybar power button.
#
# Adapted from a widely copied rofi menu that predates this project. Two things
# it inherited did not survive contact with Hyprland:
#
#   Logout branched on $DESKTOP_SESSION for openbox, bspwm, i3 and plasma, and
#   had no branch for anything else. Here $DESKTOP_SESSION is hyprland-uwsm, so
#   confirming a logout ran nothing at all.
#
#   Suspend ran `mpc -q pause` and `amixer set Master mute` first, for an mpd
#   and alsa setup this project does not have. mpc is not installed and is in no
#   package list. The mute worked, measured on a live session as [on] to [off],
#   and nothing anywhere undid it, so suspending from this menu left the machine
#   silent after resume.

dir="$HOME/.config/rofi"
theme='powermenu/style'

uptime="$(uptime -p | sed -e 's/up //g')"

# Options
shutdown='⏻'
reboot='󰑐'
lock=''
suspend='󰒲'
logout=''
yes=''
no='󰜺'

# Rofi CMD
rofi_cmd() {
	rofi -dmenu \
		-p "Power Menu" \
		-mesg "Uptime: $uptime" \
		-theme "${dir}/${theme}.rasi"
}

# Confirmation CMD
confirm_cmd() {
	rofi -dmenu \
		-p 'Confirmation' \
		-mesg 'Are you Sure?' \
		-theme "${dir}/confirm.rasi"
}

# Ask for confirmation
confirm_exit() {
	echo -e "$yes\n$no" | confirm_cmd
}

# Pass variables to rofi dmenu
run_rofi() {
	echo -e "$lock\n$suspend\n$logout\n$reboot\n$shutdown" | rofi_cmd
}

# Confirm, then act. Anything other than yes leaves without doing anything.
run_cmd() {
	local selected
	selected="$(confirm_exit)"
	[[ $selected == "$yes" ]] || exit 0

	case "$1" in
		--shutdown) hyprshutdown -t 'Shutting down...' --post-cmd 'shutdown -P 0' ;;
		--reboot) hyprshutdown -t 'Restarting...' --post-cmd 'reboot' ;;
		--suspend) systemctl suspend ;;
		# hyprsimple's own logout, the same one SUPER + X runs. It closes windows
		# so applications shut down cleanly, then stops the uwsm session.
		--logout) "$HOME/.local/bin/hypr-logout.sh" ;;
	esac
}

# Actions
chosen="$(run_rofi)"
case "$chosen" in
    "$shutdown")
		run_cmd --shutdown
        ;;
    "$reboot")
		run_cmd --reboot
        ;;
    "$lock")
        hyprlock
        ;;
    "$suspend")
		run_cmd --suspend
        ;;
    "$logout")
		run_cmd --logout
        ;;
esac
