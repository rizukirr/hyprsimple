#!/bin/bash
# The repository committed systemd's enable state alongside its units, and two
# of those symlinks pointed into /home/rizki, a home directory that exists on
# nobody's machine. cp -r copies a broken symlink happily, exit 0, so every
# install since has planted one and nothing said so.
#
# It is the second time this class has shipped. migrations/1787389156.sh repairs
# a hardcoded /home/rizki path in hyprpaper.conf. That fix was made to the one
# file somebody noticed, and two more instances sat in the systemd tree.
#
# So the rule is checked rather than remembered: nothing this repository tracks
# may carry a path into a particular person's home.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

cd "$REPO" || exit 1

# ---- no committed symlink escapes the repository -------------------------
#
# Every symlink here was systemd enable state, which belongs to a machine
# rather than to a configuration, and which install.sh recreates correctly with
# systemctl --user enable. A relative symlink inside the tree would be fine, an
# absolute one never is: it names a path on whoever's machine made it.

mapfile -t symlinks < <(git ls-files -s | awk '$1=="120000"{print $4}')

escaping=()
for link in "${symlinks[@]}"; do
  target="$(readlink "$link")"
  [[ $target == /* ]] && escaping+=("$link -> $target")
done

# printf runs once with no arguments when the array is empty, so the format
# string prints on its own and a clean result reads as "; " rather than "".
escaping_str=""
(( ${#escaping[@]} > 0 )) && escaping_str="$(printf '%s; ' "${escaping[@]}")"

check "no tracked symlink points at an absolute path" "$escaping_str" ""

# ---- no tracked file carries somebody's home directory -------------------
#
# Migrations are excluded because they exist to repair exactly this, so the
# path has to appear in them. Everything else has no reason to name one.

mapfile -t hardcoded < <(
  git grep -lI -E '/home/[a-z][a-z0-9_-]*/' -- . \
    ':!migrations' ':!docs' ':!external' ':!test/committed-symlinks-test.sh' 2>/dev/null
)

hardcoded_str=""
(( ${#hardcoded[@]} > 0 )) && hardcoded_str="$(printf '%s; ' "${hardcoded[@]}")"

check "no tracked file outside migrations names a specific home directory" \
  "$hardcoded_str" ""

# ---- what should still be shipped ----------------------------------------

for unit in battery-monitor.service battery-monitor.timer; do
  if [[ -f $REPO/.config/systemd/user/$unit ]]; then
    pass "$unit is still shipped, because a unit is configuration"
  else
    fail "$unit is missing, and the battery monitor cannot run without it"
  fi
done

check "no .wants or .target.wants directory is tracked, that is enable state" \
  "$(git ls-files '.config/systemd/*wants*' | wc -l)" "0"

# ---- install.sh still enables everything the symlinks used to encode -----
#
# Deleting them is only safe because these two lines put them back, correctly
# and under the right home. pipewire.service carries Also=pipewire.socket and
# WantedBy=default.target, and wireplumber.service carries
# Alias=pipewire-session-manager.service and WantedBy=pipewire.service, so
# enabling those three recreates all six of the pipewire links.

check "install.sh enables the pipewire units" \
  "$(grep -c 'systemctl --user enable --now pipewire pipewire-pulse wireplumber' "$REPO/install.sh")" "1"
# The battery timer is enabled without --now. It is wanted by
# graphical-session.target, and the install runs from a TTY or another session
# where that target is not up, so --now started a timer that would fire
# battery-monitor.sh with no compositor: on a low battery that dims the panel
# and sends a notification into a bus with no display. The symlink is what this
# suite is about, and enable alone still writes it.
check "install.sh enables the battery monitor timer" \
  "$(grep -c 'systemctl --user enable battery-monitor.timer$' "$REPO/install.sh")" "1"
check "and does not start it there, where there is no session to notify" \
  "$(grep -c 'enable --now battery-monitor.timer' "$REPO/install.sh")" "0"

# ---- the migration --------------------------------------------------------

MIGRATION="$REPO/migrations/1788533893.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

if [[ -f $MIGRATION ]]; then
  pass "the migration this suite tests exists"
else
  fail "$MIGRATION is missing, so every check below is testing nothing"
fi

wants_dir() { printf '%s' "$1/.config/systemd/user/default.target.wants"; }

setup_home() {
  local home="$TMP/$1"
  rm -rf "$home"
  mkdir -p "$(wants_dir "$home")" "$home/.config/systemd/user"
  printf '[Unit]\n' >"$home/.config/systemd/user/battery-monitor.service"
  printf '%s' "$home"
}

run_migration() {
  # systemctl is stubbed out: the migration must not depend on a running user
  # bus, and CI has none.
  local home="$1" stub="$TMP/stub"
  mkdir -p "$stub"
  printf '#!/bin/sh\nexit 0\n' >"$stub/systemctl"
  chmod +x "$stub/systemctl"
  HOME="$home" PATH="$stub:$PATH" bash "$MIGRATION" 2>&1
}

# the broken link, which is what this is for
home="$(setup_home broken)"
ln -s /home/someone-else/.config/systemd/user/battery-monitor.service \
  "$(wants_dir "$home")/battery-monitor.service"
out="$(run_migration "$home")"
check "a link pointing at another home is removed" \
  "$([[ -L $(wants_dir "$home")/battery-monitor.service ]] && echo present || echo removed)" "removed"
check "and the removal is reported" \
  "$(printf '%s' "$out" | grep -c 'Removed')" "1"
check "and the unit file itself is untouched" \
  "$([[ -f $home/.config/systemd/user/battery-monitor.service ]] && echo kept || echo deleted)" "kept"

# a link this user enabled on purpose
home="$(setup_home deliberate)"
ln -s "$home/.config/systemd/user/battery-monitor.service" \
  "$(wants_dir "$home")/battery-monitor.service"
run_migration "$home" >/dev/null
check "a link the user enabled themselves is left alone" \
  "$([[ -L $(wants_dir "$home")/battery-monitor.service ]] && echo present || echo removed)" "present"

# A link that resolves but points outside this home. This is the case the
# "does it resolve" guard exists for: the home check alone would delete it,
# because its target is not under $HOME, and it is a working link.
home="$(setup_home elsewhere)"
mkdir -p "$TMP/systemwide"
printf '[Unit]\n' >"$TMP/systemwide/battery-monitor.service"
ln -s "$TMP/systemwide/battery-monitor.service" \
  "$(wants_dir "$home")/battery-monitor.service"
run_migration "$home" >/dev/null
check "a working link is left alone even when its target is outside the home" \
  "$([[ -L $(wants_dir "$home")/battery-monitor.service ]] && echo present || echo removed)" "present"

# a broken link that still points inside this user's home, which is their
# problem to fix and not this migration's to guess at
home="$(setup_home ownbroken)"
ln -s "$home/.config/systemd/user/nonexistent.service" \
  "$(wants_dir "$home")/battery-monitor.service"
run_migration "$home" >/dev/null
check "a broken link inside the user's own home is left alone" \
  "$([[ -L $(wants_dir "$home")/battery-monitor.service ]] && echo present || echo removed)" "present"

# nothing there at all
home="$(setup_home absent)"
out="$(run_migration "$home")"
check "with no link at all the migration says nothing and exits 0" \
  "$(printf '%s' "$out" | grep -c 'Removed')" "0"

# re-running after a removal
home="$(setup_home rerun)"
ln -s /home/someone-else/.config/systemd/user/battery-monitor.service \
  "$(wants_dir "$home")/battery-monitor.service"
run_migration "$home" >/dev/null
out="$(run_migration "$home")"
check "re-running the migration reports nothing" \
  "$(printf '%s' "$out" | grep -c 'Removed')" "0"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
