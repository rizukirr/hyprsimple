#!/bin/bash
# Exercise the real updater and manager against local origins and isolated HOME.
set -euo pipefail
# shellcheck source=test/fixtures/plugin-environment.bash
source "$(dirname "${BASH_SOURCE[0]}")/fixtures/plugin-environment.bash"
# Preserve failed delivery fixtures for diagnosis without touching a real install.
trap 'status=$?; if ((status)); then printf "Failed delivery fixture: %s\n" "$TMP" >&2; else rm -rf "$TMP"; fi' EXIT

fixture delivery
printf obsolete >"$HOME/.local/bin/hyprsimple-muslimtify.sh"
# Delivery must install the command, rather than inherit the fixture's copy.
rm "$HOME/.local/bin/hyprsimple-plugin"
export PATH="$HOME/.local/bin:$PATH"
cat >"$TMP/bin/pgrep" <<'STUB'
#!/bin/bash
[[ $* == '-x Hyprland' ]]
STUB
cat >"$TMP/bin/hyprctl" <<'STUB'
#!/bin/bash
[[ $* == reload ]] || exit 99
printf 'hyprctl reload\n' >>"$LOG"
STUB
# No service or compositor process is ever started. Unexpected calls fail closed.
for command in busctl dbus-send notify-send loginctl service rc-service; do
  printf '#!/bin/bash\nprintf "unexpected service command\\n" >&2\nexit 99\n' >"$TMP/bin/$command"
done
chmod +x "$TMP/bin/"*

# Copy committed core content into a disposable origin, never mutate the repo.
CORE_WORK="$TMP/core-work"
CORE_ORIGIN="$TMP/core-origin.git"
mkdir -p "$CORE_WORK"
git -C "$REPO" archive HEAD | tar -x -C "$CORE_WORK"
rm -f "$CORE_WORK/migrations/1791554376.sh"
rm "$CORE_WORK/migrations/1791551522.sh" "$CORE_WORK/.local/bin/hyprsimple-plugin"
git -C "$REPO" show 9c9ba72315360fc1d43868c7e1d1ca730b7186e0:.local/bin/hyprsimple-update.sh >"$CORE_WORK/.local/bin/hyprsimple-update.sh"
git init -q -b main "$CORE_WORK"
git -C "$CORE_WORK" config user.email test@example.com
git -C "$CORE_WORK" config user.name test
git -C "$CORE_WORK" add .
git -C "$CORE_WORK" commit -qm 'Before external plugin delivery'
git clone -q --bare "$CORE_WORK" "$CORE_ORIGIN"
[[ -f $CORE_ORIGIN/HEAD ]] || { echo "not ok - fixture core origin did not clone" >&2; exit 1; }
rm -rf "$HYPRSIMPLE_PATH"
git clone -q "$CORE_ORIGIN" "$HYPRSIMPLE_PATH"
[[ -d $HYPRSIMPLE_PATH/.git ]] || { echo "not ok - fixture core checkout did not clone" >&2; exit 1; }
git -C "$CORE_WORK" remote add origin "$CORE_ORIGIN"
cp "$REPO/migrations/1791551522.sh" "$REPO/migrations/1791554376.sh" "$CORE_WORK/migrations/"
cp "$REPO/.local/bin/hyprsimple-plugin" "$REPO/.local/bin/hyprsimple-update.sh" "$CORE_WORK/.local/bin/"
for shell in bashrc.sh zsh.sh fish.fish; do
  cp "$REPO/.local/bin/$shell" "$CORE_WORK/.local/bin/"
done
rm -f "$CORE_WORK/.local/bin/hyprsimple-muslimtify.sh"
printf '\n// Delivery fixture change\n' >>"$CORE_WORK/default/quickshell/shell.qml"
git -C "$CORE_WORK" add .
git -C "$CORE_WORK" commit -qm 'Deliver external plugin command and migration'
git -C "$CORE_WORK" push -q origin main
mkdir -p "$HOME/.local/state/hyprsimple/migrations" "$HOME/.config/hyprsimple"
for migration in "$CORE_WORK/migrations/"*.sh; do
  [[ $(basename "$migration") == 1791551522.sh || $(basename "$migration") == 1791554376.sh ]] && continue
  touch "$HOME/.local/state/hyprsimple/migrations/$(basename "$migration")"
done
printf '{"schemaVersion":1,"plugins":{"muslimtify":{"enabled":false,"placement":"right","settings":{"label":"Retained","custom":42},"commit":""}}}\n' >"$HOME/.config/hyprsimple/plugins.json"
run_update() {
  bash "$HOME/.local/bin/hyprsimple-update.sh" </dev/null >"$TMP/output" 2>&1
}
# Start with the real updater from the pre-delivery checkout.
cp "$HYPRSIMPLE_PATH/.local/bin/hyprsimple-update.sh" "$HOME/.local/bin/"
assert run_update
assert cmp "$CORE_WORK/.local/bin/hyprsimple-plugin" "$HOME/.local/bin/hyprsimple-plugin"
assert test -x "$HOME/.local/bin/hyprsimple-plugin"
assert marker
assert test -f "$HOME/.local/state/hyprsimple/migrations/1791554376.sh"
assert test ! -e "$HOME/.local/bin/hyprsimple-muslimtify.sh"
for shell in bashrc.sh zsh.sh fish.fish; do
  assert cmp "$REPO/.local/bin/$shell" "$HOME/.local/bin/$shell"
  if grep -qE 'muslimtify-(add|remove)' "$HOME/.local/bin/$shell"; then exit 1; fi
done
assert enabled
preserved
assert jq -e '.plugins.muslimtify.settings == {label:"Retained",custom:42} and .plugins.muslimtify.placement == "right"' "$HOME/.config/hyprsimple/plugins.json"
assert grep -q 'The bar changed, restarting it' "$TMP/output"
assert grep -qx 'hyprctl reload' "$LOG"
assert test "$(readlink "$HOME/.config/hypr/hyprsimple")" == "$HYPRSIMPLE_PATH/default/hypr"
PLUGIN="$HOME/.local/share/hyprsimple-plugins/muslimtify"
assert test "$(git -C "$PLUGIN" rev-parse HEAD)" == 2f2b9028b3833e6cb4dc25b5b138fc18ef74bfea
echo 'ok - updater delivers command, runs real migration, preserves settings and reloads core'

# Give the plugin a separate local origin that can advance without any network.
git clone -q "$PLUGIN_ORIGIN" "$TMP/plugin-origin"
[[ -f $TMP/plugin-origin/manifest.json ]] || { echo "not ok - fixture plugin origin did not clone" >&2; exit 1; }
export PLUGIN_ORIGIN="$TMP/plugin-origin"
# The redirecting clone stub records its local URL. Restore the production URL
# so subsequent acquisition passes through the same pinned-origin redirect.
git -C "$PLUGIN" remote set-url origin https://github.com/muslimtify-org/muslimtify-hyprsimple.git
git -C "$PLUGIN_ORIGIN" config user.email test@example.com
git -C "$PLUGIN_ORIGIN" config user.name test
printf 'first external update\n' >"$PLUGIN_ORIGIN/delivery-proof"
git -C "$PLUGIN_ORIGIN" add delivery-proof
git -C "$PLUGIN_ORIGIN" commit -qm 'External plugin update'
next_plugin=$(git -C "$PLUGIN_ORIGIN" rev-parse HEAD)
old_plugin=$(git -C "$PLUGIN" rev-parse HEAD)
cp "$HOME/.config/hyprsimple/plugins.json" "$TMP/registered-config"
acquisitions=$(grep -c '^https://github.com/' "$LOG")
printf '\n# Later core update fixture\n' >>"$CORE_WORK/default/hypr/hypridle.conf"
git -C "$CORE_WORK" add .
git -C "$CORE_WORK" commit -qm 'Later core update'
git -C "$CORE_WORK" push -q origin main
assert run_update
assert test "$(git -C "$HYPRSIMPLE_PATH" rev-parse HEAD)" == "$(git -C "$CORE_WORK" rev-parse HEAD)"
assert test "$(git -C "$PLUGIN" rev-parse HEAD)" == "$old_plugin"
assert cmp "$TMP/registered-config" "$HOME/.config/hyprsimple/plugins.json"
assert test "$(grep -c '^https://github.com/' "$LOG")" == "$acquisitions"
preserved
echo 'ok - later core update does not acquire or modify external plugin code or settings'

assert "$HOME/.local/bin/hyprsimple-plugin" update muslimtify
assert test "$(git -C "$PLUGIN" rev-parse HEAD)" == "$next_plugin"
assert grep -qx 'first external update' "$PLUGIN/delivery-proof"
assert test "$(git -C "$PLUGIN" remote get-url origin)" == "$PLUGIN_ORIGIN"
assert jq -e '.plugins.muslimtify.enabled and .plugins.muslimtify.settings.custom == 42 and .plugins.muslimtify.placement == "right"' "$HOME/.config/hyprsimple/plugins.json"
echo 'ok - explicit plugin update follows the independent plugin origin'

cp "$HOME/.config/hyprsimple/plugins.json" "$TMP/good-config"
printf 'echo "fixture activation failed" >&2\nexit 1\n' >"$PLUGIN_ORIGIN/scripts/enable.sh"
printf 'failed external update\n' >"$PLUGIN_ORIGIN/delivery-proof"
git -C "$PLUGIN_ORIGIN" add .
git -C "$PLUGIN_ORIGIN" commit -qm 'Fail external activation'
if "$HOME/.local/bin/hyprsimple-plugin" update muslimtify >"$TMP/output" 2>&1; then
  echo 'not ok - failed activation accepted' >&2
  exit 1
fi
assert grep -q 'fixture activation failed' "$TMP/output"
assert test "$(git -C "$PLUGIN" rev-parse HEAD)" == "$next_plugin"
assert test -z "$(git -C "$PLUGIN" status --porcelain)"
assert grep -qx 'first external update' "$PLUGIN/delivery-proof"
assert cmp "$TMP/good-config" "$HOME/.config/hyprsimple/plugins.json"
assert muslimtify daemon status
preserved
echo 'ok - failed plugin activation restores previous code, configuration and daemon'
