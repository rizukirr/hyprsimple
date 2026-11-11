#!/bin/bash
# Remove hyprsimple from this user's account.
#
# User-level only. Packages and system changes stay, because nothing records
# which packages hyprsimple added or what the system looked like before it. The
# report at the end lists them.
#
# The checkout is the record of what is ours. A script is removed only when the
# checkout has one of that name with the same content. Anything the user may have
# edited is moved to <name>.hyprsimple-removed.
#
# HYPRSIMPLE_SESSION_DIR, HYPRSIMPLE_PLUGIN_ROOT and HYPRSIMPLE_SDDM_ROOT override
# paths, for the test suite.
#
# No set -e. A step that fails is reported and the others still run.
set -uo pipefail

CHECKOUT="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}"
BIN="$HOME/.local/bin"
CONFIG="$HOME/.config"
UNITS="$CONFIG/systemd/user"
STATE="$HOME/.local/state/hyprsimple"
MARKERS="$STATE/uninstall"
PLUGIN_ROOT="${HYPRSIMPLE_PLUGIN_ROOT:-$HOME/.local/share/hyprsimple-plugins}"
SESSION_FILE="${HYPRSIMPLE_SESSION_DIR:-/usr/local/share/wayland-sessions}/hyprsimple.desktop"
SDDM_ROOT="${HYPRSIMPLE_SDDM_ROOT:-/etc}"
SELF="$BIN/hyprsimple-uninstall.sh"
RC_COMMENT="# hyprsimple shell init (added by terminal.sh)"

failed=0

refuse() {
  printf 'hyprsimple-uninstall: %s\nNothing was changed.\n' "$1" >&2
  exit 1
}

problem() {
  printf 'Could not %s\n' "$1" >&2
  failed=1
}

if [[ $(id -u) == 0 ]]; then
  refuse "run this as your own user, not as root."
fi
if [[ ! -d $CHECKOUT/.local/bin ]]; then
  refuse "there is no hyprsimple checkout at $CHECKOUT, and it is the record of what to remove."
fi
if [[ $CHECKOUT == "/" || $CHECKOUT == "$HOME" || $CHECKOUT == "$HOME/" ]]; then
  refuse "$CHECKOUT is not a place a checkout can be removed from."
fi
if [[ ! -t 0 ]]; then
  refuse "this asks for confirmation, so it needs a terminal."
fi

# The shipped ~/.config items. systemd is left out because that folder also holds
# the user's own units, so only the files hyprsimple ships there are touched.
config_items=()
for item in "$CHECKOUT/.config"/*; do
  [[ -e $item ]] || continue
  name=$(basename "$item")
  [[ $name == systemd ]] || config_items+=("$name")
done

# Read now, since this moves aside with the rest of uwsm.
has_nvidia_block=0
if grep -qsF '# >>> hyprsimple nvidia >>>' "$CONFIG/uwsm/env"; then
  has_nvidia_block=1
fi

# Whether the checkout holds anything that exists nowhere else. A checkout git
# cannot answer for counts as holding something.
checkout_is_disposable() {
  local status unpushed
  status=$(git -C "$CHECKOUT" status --porcelain 2>/dev/null) || return 1
  [[ -z $status ]] || return 1
  unpushed=$(git -C "$CHECKOUT" rev-list HEAD --not --remotes --tags -1 2>/dev/null) || return 1
  [[ -z $unpushed ]]
}

# The first free <path>.hyprsimple-removed, numbered when that is taken.
aside_name() {
  local candidate="$1.hyprsimple-removed" n=2
  while [[ -e $candidate || -L $candidate ]]; do
    candidate="$1.hyprsimple-removed.$n"
    n=$((n + 1))
  done
  printf '%s' "$candidate"
}

move_aside() {
  [[ -e $1 || -L $1 ]] || return 0
  local target
  target=$(aside_name "$1")
  if mv -- "$1" "$target"; then
    printf 'Moved %s to %s\n' "$1" "$target"
  else
    problem "move $1 aside."
    return 1
  fi
}

# <path>.backup is the oldest backup, so it is what was there before hyprsimple.
restore_backup() {
  [[ -e $1.backup || -L $1.backup ]] || return 0
  if mv -- "$1.backup" "$1"; then
    printf 'Restored %s\n' "$1"
  else
    problem "restore $1.backup."
    return 1
  fi
}

# Handled once per machine. Without this a second run after a failure would see
# the backup just restored to a path and move it aside as if it were ours.
already_handled() {
  [[ -e $MARKERS/$1 ]]
}

mark_handled() {
  if ! { mkdir -p "$MARKERS" && : >"$MARKERS/$1"; }; then
    problem "record that $1 was handled."
  fi
}

remove_login_entry() {
  [[ -e $SESSION_FILE ]] || return 0
  bash "$CHECKOUT/.local/bin/hyprsimple-session.sh" remove || problem "remove the login entry at $SESSION_FILE."
}

remove_plugins() {
  local manager="$BIN/hyprsimple-plugin" ids id ok=1
  if [[ -d $PLUGIN_ROOT && -x $manager ]]; then
    # pipefail makes this fail when the list does. No list is not an empty list:
    # removing the folder then would skip each plugin's disable step.
    if ! ids=$("$manager" list 2>/dev/null | cut -f1); then
      problem "list the installed plugins. Fix ~/.config/hyprsimple/plugins.json and run this again."
      return 1
    fi
    for id in $ids; do
      if ! "$manager" remove "$id"; then
        problem "remove the plugin $id."
        ok=0
      fi
    done
  fi
  if ((ok)) && [[ -d $PLUGIN_ROOT ]]; then
    rm -rf -- "$PLUGIN_ROOT" || problem "remove $PLUGIN_ROOT."
  fi
  already_handled config-hyprsimple && return 0
  move_aside "$CONFIG/hyprsimple" && mark_handled config-hyprsimple
}

stop_session_parts() {
  local unit shipped name
  qs kill -p "$CHECKOUT/default/quickshell" --any-display >/dev/null 2>&1

  # hyprpaper and hyprsunset are stock units hyprsimple enabled. pipewire and
  # hyprpolkitagent stay, since any desktop may need them.
  for unit in battery-monitor.timer battery-monitor.service hyprsimple-audio-autoswitch.service \
    hyprpaper.service hyprsunset.service; do
    systemctl --user disable --now "$unit" >/dev/null 2>&1
  done

  for shipped in "$CHECKOUT/.config/systemd/user"/*; do
    [[ -f $shipped ]] || continue
    name=$(basename "$shipped")
    if [[ -e $UNITS/$name ]]; then
      if cmp -s "$shipped" "$UNITS/$name"; then
        rm -f -- "$UNITS/$name" || problem "remove $UNITS/$name."
      else
        move_aside "$UNITS/$name"
      fi
    fi
  done
  rm -f -- "$UNITS/hyprsunset.service.d/10-hyprsimple.conf" || problem "remove the hyprsunset drop-in."
  rmdir "$UNITS/hyprsunset.service.d" 2>/dev/null
  systemctl --user daemon-reload >/dev/null 2>&1
}

# Only the two lines the installer added. cat rather than mv, so a dotfile
# manager's symlink and the file's mode survive.
clean_rc() {
  local rc=$1 source_line=$2 kept no_final_newline=0
  [[ -f $rc ]] || return 0
  grep -qxF -e "$RC_COMMENT" -e "$source_line" "$rc" || return 0
  kept=$(mktemp) || { problem "edit $rc."; return 1; }
  # grep ends its output with a newline whether or not the file did.
  [[ -z $(tail -c 1 "$rc") ]] || no_final_newline=1
  grep -vxF -e "$RC_COMMENT" -e "$source_line" "$rc" >"$kept"
  if ((no_final_newline)); then
    truncate -s -1 "$kept"
  fi
  if cat "$kept" >"$rc"; then
    printf 'Removed the hyprsimple lines from %s\n' "$rc"
  else
    problem "edit $rc."
  fi
  rm -f -- "$kept"
}

clean_shell_config() {
  clean_rc "$HOME/.bashrc" 'source ~/.local/bin/bashrc.sh'
  clean_rc "$HOME/.zshrc" 'source ~/.local/bin/zsh.sh'
  clean_rc "$CONFIG/fish/config.fish" 'source ~/.local/bin/fish.fish'
}

restore_config() {
  local name
  for name in "${config_items[@]}"; do
    already_handled "config-$name" && continue
    if move_aside "$CONFIG/$name" && restore_backup "$CONFIG/$name"; then
      mark_handled "config-$name"
    fi
  done
}

remove_scripts() {
  local shipped name target
  for shipped in "$CHECKOUT/.local/bin"/*; do
    [[ -f $shipped ]] || continue
    name=$(basename "$shipped")
    target="$BIN/$name"
    [[ $target == "$SELF" ]] && continue
    already_handled "script-$name" && continue
    if [[ -e $target || -L $target ]]; then
      if cmp -s "$shipped" "$target"; then
        rm -f -- "$target" || { problem "remove $target."; continue; }
      else
        move_aside "$target" || continue
      fi
    fi
    restore_backup "$target" && mark_handled "script-$name"
  done
}

remove_checkout() {
  if checkout_is_disposable; then
    rm -rf -- "$CHECKOUT" || problem "remove $CHECKOUT."
    return
  fi
  printf 'The checkout has work that exists nowhere else, so it is kept.\n'
  move_aside "$CHECKOUT"
}

report() {
  cat <<REPORT

Left in place:
  - Packages. Nothing records which ones hyprsimple installed.
  - System changes: NetworkManager and DNS setup, ufw rules, enabled system services and any NVIDIA udev rule. The FAQ lists how to undo them: https://rizukirr.github.io/hyprsimple-web/docs/faq#what-does-hyprsimple-uninstallsh-leave-behind
  - pipewire and hyprpolkitagent, which any desktop may need.
  - Older backups named *.backup.<number>, under ~/.config and ~/.local/bin.
  - Scripts from older hyprsimple versions in ~/.local/bin, which the checkout no longer names.
  - ~/.cache, GTK settings and gsettings values from the theme.
  - Anything moved aside, named *.hyprsimple-removed. Delete those when you no longer want them.
REPORT
  if ((has_nvidia_block)); then
    printf '\nThe NVIDIA settings hyprsimple wrote moved aside with ~/.config/uwsm. Your own Hyprland setup may need them.\n'
  fi
  if grep -qsE '^[[:space:]]*Session=hyprsimple' "$SDDM_ROOT/sddm.conf" "$SDDM_ROOT"/sddm.conf.d/*; then
    printf '\nSDDM is set to log in to the Hyprsimple entry automatically. Change Session= in %s before you log out.\n' "$SDDM_ROOT/sddm.conf"
  fi
}

printf 'This removes hyprsimple from your account.\n\n'
printf 'Removed:\n'
printf '  - The login entry, plugins, the bar, hyprsimple services and shell lines\n'
printf '  - Scripts in %s that match the checkout\n' "$BIN"
printf '  - The checkout at %s, unless it holds work that exists nowhere else\n' "$CHECKOUT"
printf '  - %s\n' "$STATE"
printf '\nMoved to <name>.hyprsimple-removed, with any .backup put back:\n'
for name in "${config_items[@]}" hyprsimple; do
  if [[ -e $CONFIG/$name || -L $CONFIG/$name ]]; then
    printf '  - %s/%s\n' "$CONFIG" "$name"
  fi
done
printf '\nPackages and system changes stay. Type yes to continue: '
read -r answer
if [[ $answer != yes ]]; then
  printf 'Nothing was changed.\n'
  exit 0
fi

remove_login_entry
remove_plugins
stop_session_parts
clean_shell_config
restore_config

# Scripts and the checkout are what a second run needs, so they go only after
# everything else worked.
if ((failed == 0)); then
  remove_scripts
fi
if ((failed == 0)); then
  remove_checkout
fi
if ((failed == 0)); then
  rm -rf -- "$STATE" || problem "remove $STATE."
fi

report

if ((failed != 0)); then
  printf '\nSomething above did not finish. Run hyprsimple-uninstall.sh again once it is fixed.\n' >&2
  exit 1
fi

printf '\nDone. Log out now: this session has lost its bar and config.\n'
rm -f -- "$SELF"
exit 0
