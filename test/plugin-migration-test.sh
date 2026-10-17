#!/bin/bash
# Real migration runner and published plugin code, with isolated system effects.
set -euo pipefail
# shellcheck source=test/fixtures/plugin-environment.bash
source "$(dirname "${BASH_SOURCE[0]}")/fixtures/plugin-environment.bash"
fixture installed
rm "$HOME/.local/bin/hyprsimple-plugin"
assert run_migration
assert marker
assert test -x "$HOME/.local/bin/hyprsimple-plugin"
assert cmp "$HYPRSIMPLE_PATH/.local/bin/hyprsimple-plugin" "$HOME/.local/bin/hyprsimple-plugin"
assert enabled
preserved
before=$(wc -l <"$LOG")
assert run_migration
assert test "$(wc -l <"$LOG")" == "$before"
echo 'ok - installed integration migrates once and preserves user files'

fixture absent
rm "$HOME/.local/bin/hyprsimple-plugin"
# Hide the command even on hosts with a real Muslimtify installed.
printf 'command() { if [[ $* == "-v muslimtify" ]]; then return 1; fi; builtin command "$@"; }\n' >"$TMP/absent-env"
BASH_ENV="$TMP/absent-env" assert run_migration
assert marker
assert test ! -d "$HOME/.local/share/hyprsimple-plugins/muslimtify"
assert test -x "$HOME/.local/bin/hyprsimple-plugin"
assert cmp "$HYPRSIMPLE_PATH/.local/bin/hyprsimple-plugin" "$HOME/.local/bin/hyprsimple-plugin"
echo 'ok - absent integration receives the manager without installing the plugin'

fixture missing-source
rm "$HYPRSIMPLE_PATH/.local/bin/hyprsimple-plugin"
cp "$HOME/.local/bin/hyprsimple-plugin" "$TMP/old-manager"
if run_migration; then echo 'not ok - missing manager source accepted'; exit 1; fi
assert test ! -f "$HOME/.local/state/hyprsimple/migrations/1791551522.sh"
assert cmp "$TMP/old-manager" "$HOME/.local/bin/hyprsimple-plugin"
assert test -z "$(find "$HOME/.local/bin" -name 'hyprsimple-plugin.*')"
cp "$REPO/.local/bin/hyprsimple-plugin" "$HYPRSIMPLE_PATH/.local/bin/"
assert run_migration
assert marker
assert enabled
echo 'ok - missing source preserves the installed manager and retries without a marker'

fixture disabled
export HYPRSIMPLE_PLUGIN_ROOT="$HOME/custom-plugins"
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" "$HOME/.local/bin/hyprsimple-plugin" install https://github.com/muslimtify-org/muslimtify-hyprsimple.git >"$TMP/output" 2>&1
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" "$HOME/.local/bin/hyprsimple-plugin" disable muslimtify >"$TMP/output" 2>&1
jq '.plugins.muslimtify.settings = {custom:42} | .plugins.muslimtify.placement = "right"' "$HOME/.config/hyprsimple/plugins.json" >"$TMP/config"
cp "$TMP/config" "$HOME/.config/hyprsimple/plugins.json"
assert run_migration
assert marker
assert cmp "$TMP/config" "$HOME/.config/hyprsimple/plugins.json"
preserved
echo 'ok - intentionally disabled plugin and its settings remain unchanged'

for failure in network daemon status; do
  fixture "$failure"
  export HYPRSIMPLE_PLUGIN_ROOT="$HOME/custom-plugins"
  touch "$HOME/fail-$failure"
  assert test ! -f "$HOME/.local/state/hyprsimple/migrations/1791551522.sh"
  if run_migration; then echo 'not ok - failure accepted'; exit 1; fi
  assert test ! -f "$HOME/.local/state/hyprsimple/migrations/1791551522.sh"
  assert test -f "$HOME/.local/state/hyprsimple/plugins/muslimtify-migration.pending"
  if [[ $failure == daemon || $failure == status ]]; then
    assert jq -e '.plugins.muslimtify.enabled == false' "$HOME/.config/hyprsimple/plugins.json"
    jq '.plugins.muslimtify.settings = {custom:42}' "$HOME/.config/hyprsimple/plugins.json" >"$TMP/config"
    cp "$TMP/config" "$HOME/.config/hyprsimple/plugins.json"
  fi
  rm "$HOME/fail-$failure"
  assert run_migration
  assert marker
  assert enabled
  assert test ! -e "$HOME/.local/state/hyprsimple/plugins/muslimtify-migration.pending"
  if [[ $failure != network ]]; then
    assert jq -e '.plugins.muslimtify.settings.custom == 42' "$HOME/.config/hyprsimple/plugins.json"
  fi
  preserved
  echo "ok - $failure failure has no completion marker and retries successfully"
done

fixture enabled
env HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" "$HOME/.local/bin/hyprsimple-plugin" install https://github.com/muslimtify-org/muslimtify-hyprsimple.git >"$TMP/output" 2>&1
rm "$HOME/running"
before=$(wc -l <"$LOG")
assert run_migration
assert marker
assert enabled
assert test ! -e "$HOME/.local/state/hyprsimple/plugins/muslimtify-migration.pending"
assert test "$(wc -l <"$LOG")" == "$before"
assert test ! -e "$HOME/running"
preserved
echo 'ok - enabled plugin completes without daemon status calls or extra installation'
