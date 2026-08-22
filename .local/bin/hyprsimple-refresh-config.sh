#!/bin/bash

# Copy a default config from the hyprsimple repo into ~/.config, keeping a
# timestamped backup only when the file actually changed.
#
#   hyprsimple-refresh-config.sh hypr/hyprlock.conf
#
# copies ~/.local/share/hyprsimple/.config/hypr/hyprlock.conf
#     to ~/.config/hypr/hyprlock.conf

HYPRSIMPLE_PATH="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}"

config_file="$1"

if [[ -z $config_file ]]; then
  cat <<USAGE
Usage: $(basename "$0") <config-path>

Provide a path relative to the .config directory, e.g.

  $(basename "$0") hypr/hyprlock.conf
USAGE
  exit 1
fi

default_config_file="$HYPRSIMPLE_PATH/.config/$config_file"
user_config_file="$HOME/.config/$config_file"
backup_config_file="$user_config_file.bak.$(date +%s)"

if [[ ! -f $default_config_file ]]; then
  echo "No such default config: $default_config_file" >&2
  exit 1
fi

mkdir -p "$(dirname "$user_config_file")"

if [[ ! -f $user_config_file ]]; then
  cp -f "$default_config_file" "$user_config_file"
  echo "Installed new config: $user_config_file"
  exit 0
fi

cp -f "$user_config_file" "$backup_config_file"
cp -f "$default_config_file" "$user_config_file"

# Nothing changed, so there is nothing worth keeping a backup of
if cmp -s "$user_config_file" "$backup_config_file"; then
  rm -f "$backup_config_file"
  exit 0
fi

echo -e "\033[0;31mReplaced $user_config_file with the new hyprsimple default."
echo -e "Saved your previous version as $backup_config_file.\033[0m"
echo -e "\n\033[0;32mChanges (< new, > yours):\033[0m"
diff "$user_config_file" "$backup_config_file" || true
