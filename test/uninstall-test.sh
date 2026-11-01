#!/bin/bash
# Runs the real uninstaller against a fake home and a fake checkout.
#
# Everything it could reach on a desktop is a stand-in: systemctl, qs, uwsm and
# sudo. The checkout holds the repository's real scripts and the names of its real
# config items, with small contents, since the themes are large.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}
for helper in pass fail check; do
  declare -F "$helper" >/dev/null || { printf 'not ok - helper %s missing\n' "$helper" >&2; exit 1; }
done

STUB="$TMP/stub"; mkdir -p "$STUB"
for tool in qs uwsm; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$tool"
done
cat >"$STUB/systemctl" <<STUBEOF
#!/bin/bash
printf '%s\n' "\$*" >>"$TMP/systemctl.log"
STUBEOF
# A sudo that refuses, so a login entry in a locked folder cannot be removed.
printf '#!/bin/bash\nexit 1\n' >"$STUB/sudo"
chmod +x "$STUB"/*

H="$TMP/home"
CO="$TMP/checkout"
SESSIONS="$TMP/sessions"
SDDM="$TMP/sddm"
SCRIPT="$H/.local/bin/hyprsimple-uninstall.sh"

fresh() {
  chmod -R u+w "$TMP" 2>/dev/null
  rm -rf "$H" "$CO" "$SESSIONS" "$SDDM" "$TMP/origin.git"
  : >"$TMP/systemctl.log"
  mkdir -p "$H/.local/bin" "$H/.config/systemd/user" "$CO/.local/bin" "$CO/.config/systemd/user" \
    "$CO/default/quickshell" "$H/.local/state/hyprsimple/migrations" "$SESSIONS" "$SDDM" \
    "$H/.local/share/hyprsimple-plugins/demo" "$H/.config/hyprsimple"

  cp "$REPO"/.local/bin/* "$CO/.local/bin/"
  cp "$REPO"/.local/bin/* "$H/.local/bin/"
  chmod +x "$H"/.local/bin/*

  # Named as the repository names them, so a new config item is covered.
  local item name
  for item in "$REPO"/.config/*; do
    name=$(basename "$item")
    [[ $name == systemd ]] && continue
    if [[ -d $item ]]; then
      mkdir -p "$CO/.config/$name" "$H/.config/$name"
      printf 'shipped\n' >"$CO/.config/$name/file"
      printf 'shipped\n' >"$H/.config/$name/file"
    else
      printf 'shipped\n' >"$CO/.config/$name"
      printf 'shipped\n' >"$H/.config/$name"
    fi
  done

  cp "$REPO"/.config/systemd/user/* "$CO/.config/systemd/user/"
  cp "$REPO"/.config/systemd/user/* "$H/.config/systemd/user/"
  printf 'mine\n' >"$H/.config/systemd/user/my-own.service"
  mkdir -p "$H/.config/systemd/user/hyprsunset.service.d"
  ln -s "$CO/default/systemd/hyprsunset-restart.conf" "$H/.config/systemd/user/hyprsunset.service.d/10-hyprsimple.conf"

  printf '{"schemaVersion":1,"apiVersion":1,"id":"demo","name":"Demo","version":"1","entryPoints":{"widget":"Widget.qml"}}\n' \
    >"$H/.local/share/hyprsimple-plugins/demo/manifest.json"
  printf 'x\n' >"$H/.local/share/hyprsimple-plugins/demo/Widget.qml"
  printf '{"schemaVersion":1,"plugins":{"demo":{"enabled":true,"placement":"left","settings":{}}}}\n' \
    >"$H/.config/hyprsimple/plugins.json"

  git init -q --bare "$TMP/origin.git"
  git -C "$CO" init -q
  git -C "$CO" remote add origin "$TMP/origin.git"
  git -C "$CO" add -A
  git -C "$CO" -c user.email=t@example.com -c user.name=t commit -qm checkout
  git -C "$CO" push -q origin HEAD
}

# Through script, since the uninstaller insists on a terminal.
run_uninstall() {
  printf '%s\n' "$1" | script -qec "env HOME=$H HYPRSIMPLE_PATH=$CO HYPRSIMPLE_SESSION_DIR=$SESSIONS HYPRSIMPLE_SDDM_ROOT=$SDDM XDG_CONFIG_HOME=$H/.config PATH=$STUB:/usr/bin:/bin bash $SCRIPT" /dev/null >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}
rc() { cat "$TMP/rc"; }
gone() { [[ -e $1 || -L $1 ]] && echo there || echo gone; }
snapshot() { (cd "$H" && find . -printf '%p %y\n' | LC_ALL=C sort; find . -type f -exec md5sum {} + | LC_ALL=C sort); }

# ---- a confirmed run --------------------------------------------------------

fresh
printf 'my edit\n' >"$H/.config/hypr/file"
mkdir -p "$H/.config/ghostty.backup"
printf 'my old ghostty\n' >"$H/.config/ghostty.backup/file"
printf 'edited\n' >>"$H/.local/bin/screenshot.sh"
printf 'my script\n' >"$H/.local/bin/my-script.sh"
printf 'my older zsh setup\n' >"$H/.local/bin/zsh.sh.backup"
printf 'source ~/mine.sh\n\n# hyprsimple shell init (added by terminal.sh)\nsource ~/.local/bin/bashrc.sh\nalias keep=me\n' >"$H/.bashrc"
printf '# hyprsimple shell init (added by terminal.sh)\nsource ~/.local/bin/zsh.sh\nalias keepz=me\n' >"$H/.zshrc"
mkdir -p "$H/.config/fish"
printf 'set keep me\n# hyprsimple shell init (added by terminal.sh)\nsource ~/.local/bin/fish.fish\n' >"$H/.config/fish/config.fish"
printf '# >>> hyprsimple nvidia >>>\nexport NVD_BACKEND=direct\n# <<< hyprsimple nvidia <<<\n' >"$H/.config/uwsm/env"
printf 'entry\n' >"$SESSIONS/hyprsimple.desktop"
printf '[Autologin]\nSession=hyprsimple\n' >"$SDDM/sddm.conf"

run_uninstall yes
check "a confirmed run exits 0" "$(rc)" "0"

check "an edited config survives aside" "$(cat "$H/.config/hypr.hyprsimple-removed/file" 2>/dev/null)" "my edit"
check "and the path is free when it had no backup" "$(gone "$H/.config/hypr")" "gone"
check "a shipped config moves aside" "$(cat "$H/.config/ghostty.hyprsimple-removed/file" 2>/dev/null)" "shipped"
check "and its backup is back" "$(cat "$H/.config/ghostty/file" 2>/dev/null)" "my old ghostty"
check "with no backup file left over" "$(gone "$H/.config/ghostty.backup")" "gone"
for item in "$REPO"/.config/*; do
  name=$(basename "$item")
  [[ $name == systemd ]] && continue
  check "$name is moved aside" "$(gone "$H/.config/$name.hyprsimple-removed")" "there"
done

check "an unchanged script is gone" "$(gone "$H/.local/bin/theme-switcher.sh")" "gone"
check "an edited script is moved aside" "$(tail -1 "$H/.local/bin/screenshot.sh.hyprsimple-removed" 2>/dev/null)" "edited"
check "a script the checkout does not name is untouched" "$(cat "$H/.local/bin/my-script.sh" 2>/dev/null)" "my script"
check "a script's backup is back" "$(cat "$H/.local/bin/zsh.sh" 2>/dev/null)" "my older zsh setup"
check "the script removes itself" "$(gone "$SCRIPT")" "gone"

check "the user's own unit is untouched" "$(cat "$H/.config/systemd/user/my-own.service" 2>/dev/null)" "mine"
check "shipped units are gone" "$(gone "$H/.config/systemd/user/hyprsimple-audio-autoswitch.service")" "gone"
check "the drop-in is gone" "$(gone "$H/.config/systemd/user/hyprsunset.service.d/10-hyprsimple.conf")" "gone"
check "and its empty folder" "$(gone "$H/.config/systemd/user/hyprsunset.service.d")" "gone"
check "the shipped services are disabled" \
  "$(grep -c '^--user disable --now \(battery-monitor.timer\|battery-monitor.service\|hyprsimple-audio-autoswitch.service\|hyprpaper.service\|hyprsunset.service\)$' "$TMP/systemctl.log")" "5"
check "and pipewire is left running" "$(grep -c 'pipewire\|polkit' "$TMP/systemctl.log")" "0"

check "only the two bash lines go" "$(cat "$H/.bashrc")" $'source ~/mine.sh\n\nalias keep=me'
check "only the two zsh lines go" "$(cat "$H/.zshrc")" "alias keepz=me"
check "only the two fish lines go" "$(cat "$H/.config/fish/config.fish")" "set keep me"

check "the login entry is gone" "$(gone "$SESSIONS/hyprsimple.desktop")" "gone"
check "plugins are gone" "$(gone "$H/.local/share/hyprsimple-plugins")" "gone"
check "plugin settings move aside" "$(gone "$H/.config/hyprsimple.hyprsimple-removed/plugins.json")" "there"
check "the state folder is gone" "$(gone "$H/.local/state/hyprsimple")" "gone"
check "a clean checkout is deleted" "$(gone "$CO")" "gone"

for phrase in 'Packages' 'System changes' 'backup.<number>' '.cache' 'NVIDIA settings' 'Session=' 'Log out now'; do
  check "the report mentions $phrase" "$([[ $(grep -cF "$phrase" "$TMP/out") -ge 1 ]] && echo yes || echo no)" "yes"
done

# ---- no warnings a machine does not need ------------------------------------

fresh
run_uninstall yes
check "without an NVIDIA block the report does not mention one" "$(grep -c 'NVIDIA settings' "$TMP/out")" "0"
check "without an SDDM setting there is no warning" "$(grep -c 'Session=' "$TMP/out")" "0"

# ---- a name already taken ---------------------------------------------------

fresh
mkdir -p "$H/.config/hypr.hyprsimple-removed"
printf 'earlier\n' >"$H/.config/hypr.hyprsimple-removed/file"
run_uninstall yes
check "an earlier one is not overwritten" "$(cat "$H/.config/hypr.hyprsimple-removed/file")" "earlier"
check "the new one gets a number" "$(cat "$H/.config/hypr.hyprsimple-removed.2/file" 2>/dev/null)" "shipped"

# ---- nothing changes without a yes ------------------------------------------

fresh
before=$(snapshot)
run_uninstall no
check "answering no exits 0" "$(rc)" "0"
check "and changes nothing" "$(snapshot)" "$before"
run_uninstall y
check "y is not yes" "$(snapshot)" "$before"

# ---- refusals change nothing ------------------------------------------------

fresh
before=$(snapshot)
env HOME="$H" HYPRSIMPLE_PATH="$CO" PATH="$STUB:/usr/bin:/bin" bash "$SCRIPT" </dev/null >/dev/null 2>&1
check "with no terminal it fails" "$?" "1"
check "and changes nothing" "$(snapshot)" "$before"

mv "$CO" "$CO.away"
run_uninstall yes
check "with no checkout it fails" "$(rc)" "1"
check "and changes nothing" "$(snapshot)" "$before"
mv "$CO.away" "$CO"

printf '#!/bin/bash\necho 0\n' >"$STUB/id"; chmod +x "$STUB/id"
run_uninstall yes
check "as root it fails" "$(rc)" "1"
check "and changes nothing" "$(snapshot)" "$before"
rm -f "$STUB/id"

# ---- a plugin list that cannot be read --------------------------------------

fresh
printf 'not json\n' >"$H/.config/hyprsimple/plugins.json"
run_uninstall yes
check "a corrupt plugin config fails the run" "$(rc)" "1"
check "and the plugin is not deleted without its disable step" \
  "$(gone "$H/.local/share/hyprsimple-plugins/demo")" "there"
check "and the settings stay, to be fixed" "$(cat "$H/.config/hyprsimple/plugins.json")" "not json"
check "and the checkout stays for a second run" "$(gone "$CO/.local/bin")" "there"

printf '{"schemaVersion":1,"plugins":{"demo":{"enabled":true,"placement":"left","settings":{}}}}\n' \
  >"$H/.config/hyprsimple/plugins.json"
run_uninstall yes
check "once it is fixed, a second run exits 0" "$(rc)" "0"
check "and removes the plugin" "$(gone "$H/.local/share/hyprsimple-plugins")" "gone"

# ---- a checkout with work in it ---------------------------------------------

fresh
printf 'local change\n' >>"$CO/.local/bin/screenshot.sh"
cp "$CO/.local/bin/screenshot.sh" "$H/.local/bin/screenshot.sh"
run_uninstall yes
check "a checkout with local changes is kept" "$(gone "$CO.hyprsimple-removed/.git")" "there"
check "and its original path is free" "$(gone "$CO")" "gone"

fresh
git -C "$CO" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m unpushed
run_uninstall yes
check "a checkout with an unpushed commit is kept" "$(gone "$CO.hyprsimple-removed/.git")" "there"

# ---- a failed step, then a second run ----------------------------------------

fresh
mkdir -p "$H/.config/ghostty.backup"
printf 'my old ghostty\n' >"$H/.config/ghostty.backup/file"
printf 'entry\n' >"$SESSIONS/hyprsimple.desktop"
chmod 555 "$SESSIONS"
run_uninstall yes
check "a failed step exits non-zero" "$(rc)" "1"
check "the other steps still ran" "$(gone "$H/.config/hypr.hyprsimple-removed")" "there"
check "the checkout is kept for a second run" "$(gone "$CO/.local/bin")" "there"
check "so is the script" "$(gone "$SCRIPT")" "there"

chmod 755 "$SESSIONS"
run_uninstall yes
check "the second run exits 0" "$(rc)" "0"
check "and finishes the job" "$(gone "$SESSIONS/hyprsimple.desktop")" "gone"
check "the restored backup was not moved aside again" "$(cat "$H/.config/ghostty/file" 2>/dev/null)" "my old ghostty"
check "and no second copy was made" "$(gone "$H/.config/ghostty.hyprsimple-removed.2")" "gone"
check "the checkout is gone now" "$(gone "$CO")" "gone"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
