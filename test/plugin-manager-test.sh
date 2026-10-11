#!/bin/bash
# Real manager, isolated HOME, local repositories, and stubbed desktop/packages.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
cleanup() (
  trap 'rm -rf "$TMP"' EXIT
  if [[ -f $TMP/restart-child ]]; then
    kill "$(cat "$TMP/restart-child")" 2>/dev/null || true
  fi
)
trap cleanup EXIT
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
if [[ -n ${RESTART_CHILD_FILE:-} ]]; then
  sleep 300 </dev/null >/dev/null 2>&1 &
  printf '%s\n' "$!" >"$RESTART_CHILD_FILE"
fi
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
  jq -n --arg id "$id" '{schemaVersion:1,apiVersion:1,id:$id,name:"Fixture",version:"1",entryPoints:{panel:"Panel.qml"},lifecycle:{enable:"enable.sh",disable:"disable.sh"},panelAliases:[$id]}' >"$dir/manifest.json"
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
fixture "$TMP/refresh-lock" refresh-lock
RESTART_CHILD_FILE="$TMP/restart-child" "$MANAGER" install --local "$TMP/refresh-lock" >"$TMP/output" 2>&1
restart_child=$(cat "$TMP/restart-child")
kill -0 "$restart_child"
timeout 2 "$MANAGER" list >"$TMP/output" 2>&1 || { cat "$TMP/output" >&2; exit 1; }
kill -0 "$restart_child"
kill "$restart_child"
rm "$TMP/restart-child"
run remove refresh-lock
pass 'persistent restart child does not retain manager lock'
fixture "$TMP/source" example
run install --local "$TMP/source"
jq -e ' .plugins.example.enabled == true' "$HOME/.config/hyprsimple/plugins.json" >/dev/null
run disable example
run list
grep -q $'example\t1\tfalse' "$TMP/output"
pass 'local install automatically enables, list works'
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
for mutation in '.apiVersion=2' '.schemaVersion="1"' '.id="hyprsimple.reserved"' '.entryPoints.panel="../outside.qml"' '.entryPoints.panel="/tmp/outside.qml"' '.unexpected=true' '.dependencies.packages=["--evil"]' '.entryPoints={}' '.bindings=[]' '.lifecycle.enable="../enable.sh"'; do
  fixture "$TMP/bad" other
  jq "$mutation" "$TMP/bad/manifest.json" >"$TMP/manifest"
  mv "$TMP/manifest" "$TMP/bad/manifest.json"
  commit "$TMP/bad"
  reject "reject manifest $mutation" install --local "$TMP/bad"
  rm -rf "$TMP/bad"
done
fixture "$TMP/bad" other
jq '.panelAliases=["example"]' "$TMP/bad/manifest.json" >"$TMP/manifest"
mv "$TMP/manifest" "$TMP/bad/manifest.json"
commit "$TMP/bad"
reject 'duplicate alias across installed plugins' install --local "$TMP/bad"
rm -rf "$TMP/bad"
CONFIG="$HOME/.config/hyprsimple/plugins.json"
cp "$CONFIG" "$TMP/config"
printf '{\n' >"$CONFIG"
reject 'malformed config rejected' list
cp "$TMP/config" "$CONFIG"
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
[[ $(grep -c '^bar ' "$LOG") == 1 && $(grep -c '^hyprctl ' "$LOG") == 0 ]]
[[ ! -e $HOME/.local/state/hyprsimple/plugins/bindings.json ]]
pass 'successful enable refreshes the bar once and leaves keybindings to the user'
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
run list
pass 'concurrent installation serializes and rejects overwrite'
: >"$LOG"
unset HYPRLAND_INSTANCE_SIGNATURE
run disable concurrent
[[ $(grep -c '^bar ' "$LOG") == 1 ]]
if grep -q '^hyprctl ' "$LOG"; then exit 1; fi
pass 'inactive session does not request Hyprland reload'
# A plugin follows its releases unless a branch is asked for.
fixture "$TMP/channel" channel
git -C "$TMP/channel" tag v0.9.0
printf 'second\n' >"$TMP/channel/note"
commit "$TMP/channel"
git -C "$TMP/channel" tag v0.10.0
git -C "$TMP/channel" tag 0.9.5
printf 'unreleased\n' >"$TMP/channel/note"
commit "$TMP/channel"
installed="$HYPRSIMPLE_PLUGIN_ROOT/channel"
at() { [[ $(git -C "$installed" rev-parse HEAD) == "$(git -C "$TMP/channel" rev-parse "$1")" ]]; }
run install --local "$TMP/channel"
at v0.10.0
jq -e '.plugins.channel | has("branch") | not' "$CONFIG" >/dev/null
run list
grep -q $'channel\t1\ttrue\treleases' "$TMP/output"
pass 'install takes the newest release by number, not the tip and not the newest name'
run update channel
at v0.10.0
git -C "$TMP/channel" tag v0.11.0
run update channel
at v0.11.0
pass 'update stays on a release until a newer one is tagged'
run remove channel
branch=$(git -C "$TMP/channel" symbolic-ref --short HEAD)
printf 'tip\n' >"$TMP/channel/note"
commit "$TMP/channel"
run install --local "$TMP/channel" --branch "$branch"
at "$branch"
jq -e --arg branch "$branch" '.plugins.channel.branch == $branch' "$CONFIG" >/dev/null
run list
grep -q "channel"$'\t1\ttrue\t'"$branch" "$TMP/output"
printf 'tip again\n' >"$TMP/channel/note"
commit "$TMP/channel"
git -C "$TMP/channel" tag v0.12.0 HEAD~1
run update channel
at "$branch"
pass '--branch after the source installs that branch, and update keeps following it past newer releases'
run remove channel
run install --branch v0.9.0 --local "$TMP/channel"
at v0.9.0
run update channel
at v0.9.0
pass '--branch with a tag name pins that release'
run remove channel
run install --local "$TMP/channel"
at v0.9.0
jq -e '.plugins.channel.branch == "v0.9.0"' "$CONFIG" >/dev/null
pass 'the lock outlives removal, so a plain install goes back to it'
run update channel --stable
at v0.12.0
jq -e '.plugins.channel | has("branch") | not' "$CONFIG" >/dev/null
run update channel
at v0.12.0
pass 'update --stable unlocks and returns to the newest release'
git -C "$TMP/channel" branch dev v0.9.0
run update --branch dev channel
at dev
jq -e '.plugins.channel.branch == "dev"' "$CONFIG" >/dev/null
printf 'dev work\n' >"$TMP/dev-note"
git -C "$TMP/channel" checkout -q dev
cp "$TMP/dev-note" "$TMP/channel/note"
commit "$TMP/channel"
git -C "$TMP/channel" checkout -q "$branch"
run update channel
at dev
run disable channel
run enable channel
at dev
pass 'update --branch locks onto a branch that is not the default, and later commands keep it'
cp "$CONFIG" "$TMP/locked-config"
reject 'switching to a branch that does not exist changes nothing' update channel --branch missing
at dev
cmp "$CONFIG" "$TMP/locked-config"
reject '--branch and --stable together are refused' update channel --branch dev --stable
reject 'disable takes no channel option' disable channel --stable
reject 'remove takes no channel option' remove channel --branch dev
run remove channel
run install --local "$TMP/channel" --stable
at v0.12.0
jq -e '.plugins.channel | has("branch") | not' "$CONFIG" >/dev/null
run remove channel
pass 'install --stable clears the lock'
reject 'a branch that does not exist installs nothing' install --local "$TMP/channel" --branch missing
[[ ! -e $installed ]]
reject 'an option-like branch name is refused' install --local "$TMP/channel" --branch --upload-pack=evil
reject '--branch needs a name' install --local "$TMP/channel" --branch
reject 'two sources are refused' install --local "$TMP/channel" "$TMP/source"
reject '--local is refused outside install' update example --local
printf 'all manager checks passed\n'
