#!/bin/bash
# Real manager, isolated HOME, local repositories, and stubbed desktop/packages.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" HYPRSIMPLE_PLUGIN_ROOT="$TMP/plugins"
export HYPRSIMPLE_PATH="$REPO" LOG="$TMP/log" PACKAGE_DB="$TMP/packages"
mkdir -p "$HOME/.local/bin" "$TMP/bin" "$PACKAGE_DB"
REAL_GIT="$(command -v git)"
REAL_MV="$(command -v mv)"
export REAL_MV
export REAL_GIT
export PATH="$TMP/bin:$PATH"
MANAGER="$REPO/.local/bin/hyprsimple-plugin"
cat >"$TMP/bin/pacman" <<'STUB'
#!/bin/bash
printf 'pacman %s\n' "$*" >>"$LOG"
if [[ $1 == -Q ]]; then [[ -f $PACKAGE_DB/$2 ]]; exit; fi
[[ ! -e $PACKAGE_DB/fail ]] || exit 1
for pkg in "$@"; do [[ $pkg == -* ]] || touch "$PACKAGE_DB/$pkg"; done
STUB
cat >"$TMP/bin/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB
cat >"$TMP/bin/paru" <<'STUB'
#!/bin/bash
printf 'paru %s\n' "$*" >>"$LOG"
exec pacman "$@"
STUB
cat >"$TMP/bin/hyprctl" <<'STUB'
#!/bin/bash
printf 'hyprctl %s\n' "$*" >>"$LOG"
STUB
cat >"$HOME/.local/bin/hyprsimple-restart-bar.sh" <<'STUB'
#!/bin/bash
printf 'bar %s\n' "$*" >>"$LOG"
STUB
cat >"$TMP/bin/git" <<'STUB'
#!/bin/bash
args=("$@")
for ((i=0; i < ${#args[@]}; i++)); do
  if [[ ${args[i]} == https://github.com/* ]]; then
    printf 'github %s prompts=%s\n' "${args[i]}" "${GIT_TERMINAL_PROMPT:-unset}" >>"$LOG"
    args[i]="$GITHUB_FIXTURE"
  fi
done
exec "$REAL_GIT" "${args[@]}"
STUB
cat >"$TMP/bin/mv" <<'STUB'
#!/bin/bash
if [[ -e $HOME/fail-publish && $* == *'/repo '* ]]; then
  rm "$HOME/fail-publish"
  exit 1
fi
exec "$REAL_MV" "$@"
STUB
chmod +x "$TMP/bin/"* "$HOME/.local/bin/"*
fixture() {
  local dir=$1 id=$2
  mkdir -p "$dir"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name test
  jq -n --arg id "$id" '{schemaVersion:1,apiVersion:1,id:$id,name:"Fixture",version:"1",entryPoints:{panel:"Panel.qml"},lifecycle:{enable:"enable.sh",disable:"disable.sh"},bindings:[{key:"SUPER, P",description:"Open fixture",action:"toggle-panel"}],panelAliases:[$id]}' >"$dir/manifest.json"
  printf 'import QtQuick\nItem { required property var context }\n' >"$dir/Panel.qml"
  printf 'echo enable >>"$LOG"\n[[ ! -e "$HOME/fail-enable" ]]\n' >"$dir/enable.sh"
  printf 'echo disable >>"$LOG"\n[[ ! -e "$HOME/fail-disable" ]]\n' >"$dir/disable.sh"
  commit "$dir"
}
commit() { git -C "$1" add -A; git -C "$1" commit -qm fixture; }
pass() { printf 'ok - %s\n' "$1"; }
reject() {
  local description=$1
  shift
  if "$MANAGER" "$@" >"$TMP/output" 2>&1; then
    cat "$TMP/output" >&2
    printf 'not ok - %s\n' "$description" >&2
    exit 1
  fi
  pass "$description"
}
run() { "$MANAGER" "$@" >"$TMP/output" 2>&1 || { cat "$TMP/output" >&2; exit 1; }; }
fixture "$TMP/lock" lock
printf '[[ ! -e /proc/$$/fd/9 ]]\n' >"$TMP/lock/enable.sh"
commit "$TMP/lock"
run install --local "$TMP/lock"
run remove lock
pass 'lifecycle does not inherit manager lock'
fixture "$TMP/source" example
run validate "$TMP/source"
run install --local "$TMP/source"
jq -e ' .plugins.example.enabled == true' "$HOME/.config/hyprsimple/plugins.json" >/dev/null
run disable example
run validate
run list
grep -q $'example\t1\tfalse' "$TMP/output"
pass 'local install automatically enables, author folder validates, list works'
fixture "$TMP/direct" direct
export GITHUB_FIXTURE="$TMP/direct"
run owner/repo
grep -q 'github https://github.com/owner/repo.git prompts=0' "$LOG"
run remove direct
run https://github.com/owner/repo.git
jq -e '.plugins.direct.enabled == true' "$HOME/.config/hyprsimple/plugins.json" >/dev/null
run remove direct
pass 'bare GitHub URL and owner/repo normalize, clone without prompts, and enable'
fixture "$TMP/default" default
export GITHUB_FIXTURE="$TMP/default"
mkdir -p "$TMP/default-home/.local/bin"
cp "$HOME/.local/bin/hyprsimple-restart-bar.sh" "$TMP/default-home/.local/bin/"
env -u HYPRSIMPLE_PLUGIN_ROOT HOME="$TMP/default-home" "$MANAGER" owner/default >"$TMP/output" 2>&1
[[ -f $TMP/default-home/.local/share/hyprsimple-plugins/default/manifest.json ]]
pass 'default storage is outside core checkout'
reject 'inside-checkout plugin root rejected' validate invalid
if HYPRSIMPLE_PLUGIN_ROOT="$REPO/plugins" "$MANAGER" list >"$TMP/output" 2>&1; then exit 1; fi
[[ ! -e $REPO/plugins ]]
pass 'inside-checkout storage rejected before directory creation'
fixture "$TMP/activation" activation
touch "$HOME/fail-enable"
reject 'initial activation failure is incomplete and installed disabled' install --local "$TMP/activation"
jq -e '.plugins.activation.enabled == false' "$HOME/.config/hyprsimple/plugins.json" >/dev/null
rm "$HOME/fail-enable"
run enable activation
run remove activation
pass 'initial activation failure can retry enable'
export GITHUB_FIXTURE="$TMP/direct"
reject 'repeat install does not overwrite' install --local "$TMP/source"
for source in '-evil' 'file:///tmp/example' 'ssh://github.com/a/b' 'https://evil.com/a/b' 'https://github.com/a/b?token=x' 'git@github.com:a/b'; do
  reject "reject source $source" install "$source"
done
for mutation in '.apiVersion=2' '.schemaVersion="1"' '.id="hyprsimple.reserved"' '.entryPoints.panel="../outside.qml"' '.entryPoints.panel="/tmp/outside.qml"' '.unexpected=true' '.dependencies.packages=["--evil"]' '.entryPoints={}' '.bindings[0].action="exec"' '.lifecycle.enable="../enable.sh"'; do
  fixture "$TMP/bad" other
  jq "$mutation" "$TMP/bad/manifest.json" >"$TMP/manifest"
  mv "$TMP/manifest" "$TMP/bad/manifest.json"
  commit "$TMP/bad"
  reject "reject manifest $mutation" install --local "$TMP/bad"
  rm -rf "$TMP/bad"
done
fixture "$TMP/bad" other
ln -sf "$TMP/source/Panel.qml" "$TMP/bad/Panel.qml"
commit "$TMP/bad"
reject 'escaping QML symlink' install --local "$TMP/bad"
rm -rf "$TMP/bad"
fixture "$TMP/bad" other
mv "$TMP/bad/manifest.json" "$TMP/bad/data.json"
ln -s data.json "$TMP/bad/manifest.json"
commit "$TMP/bad"
reject 'symlink manifest' install --local "$TMP/bad"
rm -rf "$TMP/bad"
fixture "$TMP/bad" other
jq '.panelAliases=["example"]' "$TMP/bad/manifest.json" >"$TMP/manifest"
mv "$TMP/manifest" "$TMP/bad/manifest.json"
commit "$TMP/bad"
reject 'duplicate alias across installed plugins' install --local "$TMP/bad"
rm -rf "$TMP/bad"
CONFIG="$HOME/.config/hyprsimple/plugins.json"
cp "$CONFIG" "$TMP/config"
printf '{"schemaVersion":1,"plugins":{"example":{},"example":{}}}\n' >"$CONFIG"
reject 'duplicate configured IDs' validate
printf '{"schemaVersion":1,"plugins":{"example":{"enabled":true,"settings":[],"placement":"left","commit":""}}}\n' >"$CONFIG"
reject 'malformed settings' validate
cp "$TMP/config" "$CONFIG"
ln -sf "$TMP/source/Panel.qml" "$HYPRSIMPLE_PLUGIN_ROOT/example/Panel.qml"
reject 'runtime validates externally altered entries' enable example
git -C "$HYPRSIMPLE_PLUGIN_ROOT/example" restore Panel.qml
fixture "$TMP/deps" dependency
jq '.dependencies={packages:["example-package"],aur:["example-aur"]}' "$TMP/deps/manifest.json" >"$TMP/manifest"
mv "$TMP/manifest" "$TMP/deps/manifest.json"
commit "$TMP/deps"
touch "$PACKAGE_DB/fail"
reject 'dependency failure does not install code' install --local "$TMP/deps"
[[ ! -e $HYPRSIMPLE_PLUGIN_ROOT/dependency ]]
rm "$PACKAGE_DB/fail"
run install --local "$TMP/deps"
grep -q 'paru -S --needed --noconfirm --skipreview -- example-aur' "$LOG"
pass 'shared AUR helper uses unattended flags'
touch "$HOME/fail-enable"
reject 'enable lifecycle failure leaves disabled config' enable example
jq -e '.plugins.example.enabled == false' "$CONFIG" >/dev/null
rm "$HOME/fail-enable"
export HYPRLAND_INSTANCE_SIGNATURE=fixture
: >"$LOG"
run enable example
[[ $(grep -c '^bar ' "$LOG") == 1 && $(grep -c '^hyprctl ' "$LOG") == 1 ]]
jq -e '.bindings[0].pluginId == "example"' "$HOME/.local/state/hyprsimple/plugins/bindings.json" >/dev/null
pass 'successful enable refreshes once and generates declarative bindings'
touch "$HOME/fail-disable"
reject 'disable failure publishes disabled UI and permits retry' disable example
jq -e '.plugins.example.enabled == false' "$CONFIG" >/dev/null
rm "$HOME/fail-disable"
run disable example
jq '.plugins.example.settings={city:"Jakarta"}' "$CONFIG" >"$TMP/config"
mv "$TMP/config" "$CONFIG"
run enable example
printf 'dirty\n' >>"$HYPRSIMPLE_PLUGIN_ROOT/example/Panel.qml"
reject 'dirty update refused' update example
git -C "$HYPRSIMPLE_PLUGIN_ROOT/example" restore Panel.qml
cp "$CONFIG" "$TMP/old-config"
old=$(git -C "$HYPRSIMPLE_PLUGIN_ROOT/example" rev-parse HEAD)
printf 'echo candidate-enable >>"$LOG"\nexit 1\n' >"$TMP/source/enable.sh"
commit "$TMP/source"
touch "$HOME/fail-disable"
reject 'old disable failure aborts update' update example
cmp "$CONFIG" "$TMP/old-config"
rm "$HOME/fail-disable"
reject 'failed candidate activation restores old code and config' update example
[[ $(git -C "$HYPRSIMPLE_PLUGIN_ROOT/example" rev-parse HEAD) == "$old" ]]
cmp "$CONFIG" "$TMP/old-config"
pass 'rollback retains exact config and old commit'
touch "$HOME/fail-enable"
reject 'rollback restart failure is reported explicitly' update example
grep -q 'lifecycle rollback failed' "$TMP/output"
rm "$HOME/fail-enable"
printf 'exit 0\n' >"$TMP/source/enable.sh"
commit "$TMP/source"
run update example
[[ $(git -C "$HYPRSIMPLE_PLUGIN_ROOT/example" rev-parse HEAD) == "$(git -C "$TMP/source" rev-parse HEAD)" ]]
pass 'validated update activates candidate'
printf 'new content\n' >>"$TMP/source/Panel.qml"
commit "$TMP/source"
cp "$CONFIG" "$TMP/old-config"
old=$(git -C "$HYPRSIMPLE_PLUGIN_ROOT/example" rev-parse HEAD)
touch "$HOME/fail-publish"
reject 'filesystem publication failure rolls back old code and config' update example
[[ $(git -C "$HYPRSIMPLE_PLUGIN_ROOT/example" rev-parse HEAD) == "$old" ]]
cmp "$CONFIG" "$TMP/old-config"
pass 'unexpected update failure retains previous installation' 
run remove example
[[ ! -e $HYPRSIMPLE_PLUGIN_ROOT/example ]]
jq -e '.plugins.example.settings.city == "Jakarta" and .plugins.example.enabled == false' "$CONFIG" >/dev/null
run install --local "$TMP/source"
jq -e '.plugins.example.settings.city == "Jakarta"' "$CONFIG" >/dev/null
pass 'remove and reinstall preserve settings and packages'
fixture "$TMP/concurrent" concurrent
"$MANAGER" install --local "$TMP/concurrent" >"$TMP/first" 2>&1 &
first=$!
"$MANAGER" install --local "$TMP/concurrent" >"$TMP/second" 2>&1 &
second=$!
a=0; b=0
wait "$first" || a=$?
wait "$second" || b=$?
[[ $((a + b)) == 1 ]]
run validate
pass 'concurrent installation serializes and rejects overwrite'
mkdir "$HYPRSIMPLE_PLUGIN_ROOT/duplicate"
cp "$TMP/concurrent/manifest.json" "$HYPRSIMPLE_PLUGIN_ROOT/duplicate/manifest.json"
reject 'externally introduced duplicate installed ID rejected' validate
rm -rf "$HYPRSIMPLE_PLUGIN_ROOT/duplicate"
: >"$LOG"
unset HYPRLAND_INSTANCE_SIGNATURE
run disable concurrent
[[ $(grep -c '^bar ' "$LOG") == 1 ]]
if grep -q '^hyprctl ' "$LOG"; then exit 1; fi
pass 'inactive session does not request Hyprland reload' 
printf 'all manager checks passed\n'
