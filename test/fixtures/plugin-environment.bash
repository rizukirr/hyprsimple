# Shared isolated environment for the default external plugin delivery suites.
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
REAL_GIT="$(command -v git)"
export REAL_GIT
export PLUGIN_ORIGIN="${MUSLIMTIFY_PLUGIN_FIXTURE:-/tmp/muslimtify-hyprsimple}"
[[ -f $PLUGIN_ORIGIN/manifest.json ]] || { echo 'Missing published plugin fixture' >&2; exit 1; }
[[ $("$REAL_GIT" -C "$PLUGIN_ORIGIN" rev-parse HEAD) == 0a8fa79a7696662c7d2a2e4c68979cb50eda628b ]] || { echo 'Plugin fixture must use the published commit documented in README.md' >&2; exit 1; }
export LOG="$TMP/log"
mkdir -p "$TMP/bin"
cat >"$TMP/bin/git" <<'STUB'
#!/bin/bash
args=("$@")
for ((i=0; i < ${#args[@]}; i++)); do
  if [[ ${args[i]} == https://github.com/* ]]; then
    [[ ${args[i]} == https://github.com/muslimtify-org/muslimtify-hyprsimple.git ]] || exit 1
    echo "${args[i]}" >>"$LOG"
    [[ ! -e $HOME/fail-network ]] || exit 1
    args[i]="$PLUGIN_ORIGIN"
  fi
done
exec "$REAL_GIT" "${args[@]}"
STUB
cat >"$TMP/bin/muslimtify" <<'STUB'
#!/bin/bash
[[ ! -e $HOME/absent ]] || exit 1
printf 'muslimtify %s\n' "$*" >>"$LOG"
case "$*" in
  'daemon install') [[ ! -e $HOME/fail-daemon ]] || exit 1; touch "$HOME/running" ;;
  'daemon status') [[ -e $HOME/running && ! -e $HOME/fail-status ]] ;;
  'daemon uninstall') rm -f "$HOME/running" ;;
  *) exit 1 ;;
esac
STUB
cat >"$TMP/bin/pacman" <<'STUB'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$LOG"
[[ $1 == -Q || $1 == -Qi ]] || exit 99
STUB
for command in sudo systemctl paru yay hyprctl qs pkill uwsm setsid; do
  printf '#!/bin/bash\necho "unexpected privileged or desktop command" >&2\nexit 99\n' >"$TMP/bin/$command"
done
printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/pgrep"
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
unset HYPRLAND_INSTANCE_SIGNATURE
fixture() {
  unset HYPRSIMPLE_PLUGIN_ROOT
  export HOME="$TMP/$1" HYPRSIMPLE_PATH="$TMP/$1/core"
  mkdir -p "$HOME/.local/bin" "$HYPRSIMPLE_PATH/migrations" "$HYPRSIMPLE_PATH/.local/bin" "$HOME/.config/muslimtify" "$HOME/.config/hypr/bindings"
  cp "$REPO/.local/bin/hyprsimple-plugin" "$REPO/.local/bin/hyprsimple-muslimtify.sh" "$HOME/.local/bin/"
  printf '#!/bin/bash\nexit 0\n' >"$HOME/.local/bin/hyprsimple-restart-bar.sh"
  chmod +x "$HOME/.local/bin/"*
  printf '{"city":"Jakarta","custom":42}\n' >"$HOME/.config/muslimtify/config.json"
  printf 'retained user bindings\n' >"$HOME/.config/hypr/bindings/system.lua"
  cp "$REPO/.local/bin/hyprsimple-plugin" "$HYPRSIMPLE_PATH/.local/bin/"
  cp "$REPO/migrations/1791551522.sh" "$HYPRSIMPLE_PATH/migrations/"
}
run_migration() {
  HOME="$HOME" HYPRSIMPLE_PATH="$HYPRSIMPLE_PATH" bash "$REPO/.local/bin/hyprsimple-migrate.sh" </dev/null >"$TMP/output" 2>&1
}
assert() { "$@" || { cat "$TMP/output" >&2; printf 'not ok: %s\n' "$*" >&2; exit 1; }; }
marker() { test -f "$HOME/.local/state/hyprsimple/migrations/1791551522.sh"; }
enabled() { jq -e '.plugins.muslimtify.enabled == true' "$HOME/.config/hyprsimple/plugins.json" >/dev/null; }
preserved() {
  assert grep -qx '{"city":"Jakarta","custom":42}' "$HOME/.config/muslimtify/config.json"
  assert grep -qx 'retained user bindings' "$HOME/.config/hypr/bindings/system.lua"
}
