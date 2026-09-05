echo "Say in each config file whether it is yours to edit"

# Every file under ~/.config that hyprsimple ships is copied once and never
# touched again, and nothing in them said so. Several are the opposite:
# hyprpaper.conf is rewritten on every wallpaper change, theme-hyprlock.conf on
# every theme switch, and parts of ghostty/config and the two rofi style.rasi
# files are rewritten too. Nothing said that either, so an edit to one of those
# was lost without explanation.
#
# Each file now opens by saying which of the two it is. This is a comment
# change and nothing else: no setting is altered.
#
# These files are yours, so one is replaced only where it is still
# byte-identical to the version hyprsimple shipped before this change. Anything
# you have edited is left exactly as it is, and listed at the end.

PAIRS="
  dunst/dunstrc 82bcec36dbf38422d5a21685e4bb63c4
  ghostty/config f394072f15399042ab97208631310b26
  hypr/bindings/applications.lua 993b9948741f3024ba2a38ff14d0f619
  hypr/hypridle.conf 0cebbd67353cc3d71724776b491165e6
  hypr/hyprpaper.conf 8424920a1069a77a7fa0aab1839dd72e
  hypr/hyprsunset.conf 290af9a61b2c12f96bacc3bced76a9ce
  hypr/monitors.lua 97f48583a87469cba85957b4edaa358f
  hypr/theme-hyprlock.conf 62fa0e46011d43d3c61731a190b38815
  pipewire/pipewire.conf.d/99-input-denoising.conf ae57d3fac4c5b092cad0c585421a99ee
  rofi/confirm.rasi 9de647466ce9aca1083ea6f937333b7f
  rofi/font.rasi eeb6a49e57758df5ddff0c925575d4c0
  rofi/keybindings/style.rasi a29b37799c490c4b224eb96ee0edf85f
  rofi/launcher/color.rasi 60d8efd868e1d1e83e31c9e8eb75f761
  rofi/launcher/config.rasi 0411f113f38b5d87a1b91872fcc59f32
  rofi/launcher/font.rasi ce6f90dc4a4cda09198cf4555a95a768
  rofi/launcher/style.rasi 026a0b04cb00d07eb1f172d72de57180
  rofi/powermenu/color.rasi 60d8efd868e1d1e83e31c9e8eb75f761
  rofi/powermenu/config.rasi 6b5173b1b90af907287979fd05be2f08
  rofi/powermenu/style.rasi 14e58e5a895cf7179d6d7c78012ac002
  rofi/theme-picker/style.rasi 2a10fd1d1f58205a6198c28cd8ec7731
  starship.toml 3bd640373abae5cdaf5c8b09eb5dd53a
  systemd/user/battery-monitor.service f0f267ddd7115f8ee840921bf48dfd08
  systemd/user/battery-monitor.timer 6c3e57c43f22bd21f8062419e2e106e2
  uwsm/env f67ab38cde26bc2a5dcf159f4526084a
  waybar/config.jsonc 30c014fd4ad8ec0b868238b70111395e
  waybar/style.css 696b0ea77ae5d87a4bd948fa419abc6e
  yazi/yazi.toml 83d15d1fd6ccb7f76a8abbd2c17df2ad
"

updated=0
skipped=()

while read -r rel sum; do
  [[ -n $rel ]] || continue
  user="$HOME/.config/$rel"
  shipped="$HYPRSIMPLE_PATH/.config/$rel"

  [[ -f $user && -f $shipped ]] || continue
  cmp -s "$user" "$shipped" && continue

  if [[ $(md5sum "$user" | cut -d' ' -f1) == "$sum" ]]; then
    cp -f "$shipped" "$user"
    updated=$((updated + 1))
  else
    skipped+=("$rel")
  fi
done <<< "$PAIRS"

if (( updated > 0 )); then
  echo "  Added the header to $updated file(s) you had not edited."
fi

if (( ${#skipped[@]} > 0 )); then
  echo "  Left alone, because you have your own version:"
  printf '    %s\n' "${skipped[@]}"
  echo "  To take hyprsimple's version of one and lose your edits:"
  echo "    hyprsimple-refresh-config.sh <path listed above>"
fi

if (( updated == 0 && ${#skipped[@]} == 0 )); then
  echo "  Nothing to do."
fi
