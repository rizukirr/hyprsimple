echo "Move the installed Muslimtify integration to the default external plugin"

set -euo pipefail
# This intent survives a failed activation that records the plugin as disabled.
pending="$HOME/.local/state/hyprsimple/plugins/muslimtify-migration.pending"
plugin="${HYPRSIMPLE_PLUGIN_ROOT:-$HOME/.local/share/hyprsimple-plugins}/muslimtify"
config="$HOME/.config/hyprsimple/plugins.json"
manager="$HOME/.local/bin/hyprsimple-plugin"

# The first update can still be running an updater that only delivers scripts.
mkdir -p "$(dirname "$manager")"
staged=$(mktemp "$manager.XXXXXX")
trap 'rm -f "$staged"' EXIT
cp "${HYPRSIMPLE_PATH:?}/.local/bin/hyprsimple-plugin" "$staged"
chmod +x "$staged"
mv -f "$staged" "$manager"

if [[ ! -e $pending ]] && ! command -v muslimtify >/dev/null 2>&1; then
  echo "Muslimtify is absent, skipping external integration"
  exit 0
fi

"$manager" validate
if [[ ! -e $pending && -d $plugin ]] &&
   jq -e '.plugins.muslimtify.enabled == false' "$config" >/dev/null; then
  echo "Keeping the existing Muslimtify plugin disabled"
  exit 0
fi

mkdir -p "$(dirname "$pending")"
touch "$pending"
# The helper retries disabled activation, and checks daemon status even when
# manager enable is a no-op. Its failure message names the recovery command.
bash "$HOME/.local/bin/hyprsimple-muslimtify.sh" add
"$manager" validate muslimtify
jq -e '.plugins.muslimtify.enabled == true' "$config" >/dev/null
muslimtify daemon status
rm -f "$pending"
