#!/bin/bash
# Execute the installer's delivery, default plugin setup, and fresh markers.
set -euo pipefail
# shellcheck source=test/fixtures/plugin-environment.bash
source "$(dirname "${BASH_SOURCE[0]}")/fixtures/plugin-environment.bash"
fixture fresh
printf obsolete >"$HOME/.local/bin/hyprsimple-muslimtify.sh"
export DOTFILES_DIR="$REPO"
# Execute the real blocks without unrelated hardware and desktop setup.
sed -n '/^for script in "\$DOTFILES_DIR\/\.local\/bin"/,/^done/p' "$REPO/install.sh" >"$TMP/install-block"
printf 'backup_if_exists() { :; }\ndebug_command() { echo fixture-debug; }\nFAILED_PACKAGES=()\nRED= GREEN= NC=\n' >"$TMP/prelude"
sed -n '/^# Install the default external integration/,/^hyprctl reload/ { /^hyprctl reload/!p; }' "$REPO/install.sh" >>"$TMP/install-block"
# Fresh installs pre-mark history, independently of direct setup.
sed -n '/^# Remove the obsolete shipped helper/,/^MIGRATION_STATE_DIR/ { /^MIGRATION_STATE_DIR/!p; }' "$REPO/install.sh" >"$TMP/markers"
sed -n '/^for migration in "\$HYPRSIMPLE_PATH\/migrations"/,/^done/p' "$REPO/install.sh" >>"$TMP/markers"
mkdir -p "$HOME/.local/state/hyprsimple/migrations/skipped"
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" MIGRATION_STATE_DIR="$HOME/.local/state/hyprsimple/migrations" bash "$TMP/markers"
assert marker
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" bash -e -c 'source "$1"; source "$2"' bash "$TMP/prelude" "$TMP/install-block" >"$TMP/output" 2>&1 || { cat "$TMP/output"; exit 1; }
assert test ! -e "$HOME/.local/bin/hyprsimple-muslimtify.sh"
assert enabled
assert test -f "$HOME/.local/share/hyprsimple-plugins/muslimtify/manifest.json"
assert grep -qx 'https://github.com/muslimtify-org/muslimtify-hyprsimple.git' "$LOG"
preserved
echo 'ok - fresh install ships manager and directly installs the default plugin despite migration markers'

# Include the actual closing report in the failed install path.
sed -n '/^if (( ${#FAILED_PACKAGES\[@\]} + ${#FAILED_PLUGINS\[@\]} > 0 )); then/,/^fi/p' "$REPO/install.sh" >>"$TMP/install-block"
fixture retry
export HYPRSIMPLE_PLUGIN_ROOT="$HOME/custom-plugins"
touch "$HOME/fail-daemon"
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" bash -e -c 'source "$1"; source "$2"; [[ ${#FAILED_PLUGINS[@]} == 1 ]]' bash "$TMP/prelude" "$TMP/install-block" >"$TMP/output" 2>&1
assert grep -q '0 package(s) and 1 plugin(s) failed' "$TMP/output"
assert grep -q 'Muslimtify: retry .*hyprsimple-plugin enable muslimtify' "$TMP/output"
assert grep -q 'Retry: .*hyprsimple-plugin enable muslimtify' "$TMP/output"
assert jq -e '.plugins.muslimtify.enabled == false' "$HOME/.config/hyprsimple/plugins.json"
rm "$HOME/fail-daemon"
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" "$HOME/.local/bin/hyprsimple-plugin" enable muslimtify >"$TMP/output" 2>&1
assert test ! -e "$HOME/.local/bin/hyprsimple-muslimtify.sh"
assert enabled
assert test -f "$HYPRSIMPLE_PLUGIN_ROOT/muslimtify/manifest.json"
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" "$HOME/.local/bin/hyprsimple-plugin" remove muslimtify >"$TMP/output" 2>&1
assert test ! -d "$HYPRSIMPLE_PLUGIN_ROOT/muslimtify"
preserved
assert test "$(grep -cE '^pacman -(R|S)' "$LOG" || true)" == 0
echo 'ok - installer records activation failure, manager retries with custom root, and removal preserves packages and settings'
assert test "$(grep -n 'if ! "$plugin_manager"' "$REPO/install.sh" | cut -d: -f1)" -lt "$(grep -n 'bash "$HOME/.local/bin/hyprsimple-restart-bar.sh"$' "$REPO/install.sh" | cut -d: -f1)"

fixture repeat
setup() {
  env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" bash -e -c 'source "$1"; source "$2"' bash "$TMP/prelude" "$TMP/install-block" >"$TMP/output" 2>&1
}
assert setup
mkdir -p "$HOME/.local/state/hyprsimple/migrations"
printf obsolete >"$HOME/.local/bin/hyprsimple-muslimtify.sh"
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" MIGRATION_STATE_DIR="$HOME/.local/state/hyprsimple/migrations" bash "$TMP/markers"
assert test ! -e "$HOME/.local/bin/hyprsimple-muslimtify.sh"
acquisitions=$(grep -c '^https://github.com/' "$LOG")
assert setup
assert test "$(grep -c '^https://github.com/' "$LOG")" == "$acquisitions"
if grep -q 'plugin(s) failed' "$TMP/output"; then exit 1; fi
rm "$HOME/running"
assert setup
assert grep -q 'daemon recovery: muslimtify daemon install' "$TMP/output"
assert grep -q 'hyprsimple-plugin enable muslimtify' "$TMP/output"
assert test "$(grep -c '^https://github.com/' "$LOG")" == "$acquisitions"
assert muslimtify daemon install
assert setup
assert enabled
preserved
echo 'ok - repeated setup enables existing code and reports explicit stopped daemon recovery'

fixture download
touch "$HOME/fail-network"
assert setup
assert grep -q 'Retry: .*hyprsimple-plugin install https://github.com/muslimtify-org/muslimtify-hyprsimple.git' "$TMP/output"
assert grep -q '0 package(s) and 1 plugin(s) failed' "$TMP/output"
assert test ! -d "$HOME/.local/share/hyprsimple-plugins/muslimtify"
rm "$HOME/fail-network"
assert setup
assert enabled
preserved
echo 'ok - download failure names manager install and retries successfully'
