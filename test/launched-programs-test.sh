#!/bin/bash
# Every program the shipped config launches has to be a program the installer
# installs. Nothing enforced that, and three things had drifted apart from it:
# uwsm, which runs every autostart entry, was never in a package list at all,
# and two keys were bound to software the installer had never heard of.
#
# A missing program is the quietest failure hyprsimple has. Hyprland execs it,
# the exec fails, and no window, message or log line says so. The whole point
# of this suite is that the list is checked by something other than a person
# remembering to check it.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

LUA_FILES=(
  "$REPO/default/hypr/autostart.lua"
  "$REPO/default/hypr/bindings"/*.lua
  "$REPO/.config/hypr/bindings"/*.lua
)

# Commands hyprsimple never installs because they arrive with the base system
# or with the toolchain any Arch machine already has. Each one is here because
# it was checked, not because it looked familiar.
BASE_COMMANDS=(
  sh              # bash provides it, and bash is not optional on Arch
  systemctl       # systemd
  dbus-update-activation-environment  # dbus, a dependency of hyprland
  cut env         # coreutils
  killall         # psmisc, which base depends on
)

# Where the command name and the package name differ. A command absent from
# this table has to be its own package name.
package_of() {
  case "$1" in
    wl-copy | wl-paste) echo wl-clipboard ;;
    wpctl) echo wireplumber ;;
    killall) echo psmisc ;;
    brave) echo brave-bin ;;
    nvim) echo neovim ;;
    wl-screenrec) echo wl-screenrec-git ;;
    *) echo "$1" ;;
  esac
}

# Every command string the shipped lua hands to Hyprland, comment lines dropped
# first so an example in a comment is not read as a binding.
cmd_strings() {
  grep -hv '^[[:space:]]*--' "${LUA_FILES[@]}" |
    grep -oE 'exec_cmd\(\[\[[^]]*\]\]|exec_cmd\("[^"]*"' |
    sed -E 's/^exec_cmd\(\[\[//; s/\]\]$//; s/^exec_cmd\("//; s/"$//'
}

# The quoted defaults in vars.lua. The two that are built by concatenating
# os.getenv("HOME") are paths into this repository rather than programs, and do
# not match the quoted form on purpose.
vars_values() {
  grep -oE '^M\.[a-zA-Z]+ = "[^"]*"' "$REPO/default/hypr/vars.lua" |
    sed -E 's/^[^"]*"//; s/"$//'
}

# One command string in, the program names it runs out. uwsm is a launcher and
# sh -c is a wrapper, so both are peeled off to reach what actually runs, and
# then each pipeline or list segment contributes its first word.
programs_in() {
  local s="$1"
  # uwsm is itself a program that has to be installed, and peeling it off is
  # what hid it: it never appeared in its own output.
  [[ $s == *"uwsm app -- "* ]] && printf 'uwsm\n'
  s="${s//uwsm app -- /}"
  s="${s//sh -c /}"
  # The quotes around an sh -c argument survive the lua string and would
  # otherwise ride along on the first and last program name.
  s="${s#\'}"
  s="${s%\'}"
  printf '%s\n' "$s" | tr '|&;' '\n' | sed -E "s/^[[:space:]']+//" | awk 'NF {print $1}'
}

mapfile -t launched < <(
  {
    cmd_strings
    vars_values
  } | while IFS= read -r line; do programs_in "$line"; done |
    # A path is a file in this repository, which the copy step covers and the
    # missing-script check in another suite already pins. A lua fragment is an
    # artefact of concatenation, not a program.
    grep -vE '^/|^\$|^"|\.lua|os\.getenv|vars\.' |
    sort -u
)

check "the extractor found the programs the config launches" \
  "$([[ ${#launched[@]} -ge 8 ]] && echo enough || echo "only ${#launched[@]}")" "enough"

# uwsm is the one this suite exists for, so name it rather than trusting the
# extractor to have kept finding it.
check "uwsm is among the launched programs" \
  "$(printf '%s\n' "${launched[@]}" | grep -cx uwsm)" "1"

packages="$(grep -hv '^[[:space:]]*#' "$REPO/packages.txt" "$REPO/aur-packages.txt" | grep -v '^[[:space:]]*$')"

for prog in "${launched[@]}"; do
  skip=0
  for base in "${BASE_COMMANDS[@]}"; do
    [[ $prog == "$base" ]] && skip=1 && break
  done
  (( skip )) && continue

  pkg="$(package_of "$prog")"
  if printf '%s\n' "$packages" | grep -qx "$pkg"; then
    pass "$prog is installed by hyprsimple (package $pkg)"
  else
    fail "$prog is launched by the shipped config but no package list installs it"
  fi
done

# Scripts have runtime dependencies that no lua file mentions. Only the ones
# with no fallback belong here: a script that checks with command -v and says
# something useful is not a silent failure.
#
# battery-monitor.sh reads the charge and the charging state through upower and
# through nothing else. Without it the script still exits 0, every 30 seconds,
# for as long as the timer is enabled, having done nothing.
HARD_SCRIPT_DEPS=(
  "battery-monitor.sh upower upower"

  # iw is how both of these find and configure a wireless interface, and
  # neither has another way. It was in no package list and nothing hyprsimple
  # installs depends on it, so it was present here only because CachyOS pulls
  # it in through cachyos-settings and wireless-regdb. On a plain Arch machine
  # with exactly this list, it would not have been there.
  "wifi-powersave.sh iw iw"

  # hotspot.sh is vendored create_ap and excluded from the lint step, but the
  # feature is aliased as `hotspot` and documented, and its dependencies are
  # this project's problem. Four of the five below are in packages.txt already
  # and are there for nothing else, which is what made the missing one stand
  # out: the access point, its DHCP, its NAT and its entropy were all provided,
  # and the tool that finds the interface was not.
  "hotspot.sh iw iw"
  "hotspot.sh hostapd hostapd"
  "hotspot.sh dnsmasq dnsmasq"
  "hotspot.sh iptables iptables"
  "hotspot.sh haveged haveged"
)

for entry in "${HARD_SCRIPT_DEPS[@]}"; do
  read -r script prog pkg <<<"$entry"
  # Comment lines are stripped first. These scripts explain in prose why they
  # call what they call, so counting every mention meant an entry stayed
  # "current" after the script had stopped using the command entirely.
  uses=$(grep -v '^[[:space:]]*#' "$REPO/.local/bin/$script" | grep -c "\\b$prog\\b")
  if (( uses == 0 )); then
    fail "$script no longer calls $prog, so remove it from HARD_SCRIPT_DEPS"
  elif printf '%s\n' "$packages" | grep -qx "$pkg"; then
    pass "$prog is installed by hyprsimple, so $script can run (package $pkg)"
  else
    fail "$script depends on $prog with no fallback but no package list installs it"
  fi
done

# A font is the same class of promise as a program: the config names it and
# something has to install it. When nothing does, fontconfig substitutes
# silently, so the lock screen or the bar renders in a font nobody chose and
# nothing anywhere says so. default/hypr/hyprlock.conf asked for Fira Semibold
# for months and every lock screen drew in Noto Sans.
font_package_of() {
  # Matched case-insensitively, because fontconfig is and the configs are not
  # consistent about it.
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    "jetbrainsmono nerd font" | "jetbrainsmono nerd font mono") echo ttf-jetbrains-mono-nerd ;;
    "iosevka nerd font") echo ttf-iosevka-nerd ;;
    *) echo "" ;;
  esac
}

mapfile -t fonts < <(
  grep -rhoE 'font[_-]?family[[:space:]]*[:=][^;#}]*' "$REPO/.config" "$REPO/default" 2>/dev/null |
    sed -E 's/^[^:=]*[:=][[:space:]]*//; s/[[:space:]]*$//' |
    sort -u
)

check "the extractor found the fonts the config names" \
  "$([[ ${#fonts[@]} -ge 1 ]] && echo enough || echo none)" "enough"

for font in "${fonts[@]}"; do
  pkg="$(font_package_of "$font")"
  if [[ -z $pkg ]]; then
    fail "the config asks for the font '$font', which no package in this table provides"
  elif printf '%s\n' "$packages" | grep -qx "$pkg"; then
    pass "the font '$font' is installed by hyprsimple (package $pkg)"
  else
    fail "the config asks for the font '$font' but no package list installs $pkg"
  fi
done

# A package named twice is installed twice, once from the repositories and once
# through the AUR helper, and the second one is a build nobody asked for.
dupes="$(printf '%s\n' "$packages" | sort | uniq -d | tr '\n' ' ')"
check "no package is listed in both packages.txt and aur-packages.txt" "${dupes:-none}" "none"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
