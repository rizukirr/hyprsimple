#!/bin/bash
# Installing without standing over the machine.
#
# The install stopped and waited a dozen times: the sudo password, twice for a
# full upgrade, once for the official package list, and once per package for
# the AUR list, each of them minutes apart. It was never a decision. Five
# package operations in install.sh already passed --noconfirm, including the
# retry inside install_packages, and four did not, so the fallback path was
# unattended and the default one was not.
#
# The rule rather than the four instances: every package operation in
# install.sh confirms nothing unless --interactive was asked for. A pacman call
# added later without it is caught here rather than by someone waiting on it.
#
# Nothing here installs a package or calls sudo for real. sudo, pacman, git and
# makepkg are stubs, and the PATH each case builds does not reach /usr/bin.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL="$REPO/install.sh"
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

BASH_BIN="$(command -v bash)"

# ---- every package operation confirms nothing -------------------------------
#
# Read out of the file rather than listed here. Whole-line comments are
# stripped, because this suite and install.sh both quote the old commands in
# theirs.

mapfile -t package_ops < <(
  sed 's/^[[:space:]]*#.*//' "$INSTALL" |
    grep -nE '(sudo pacman -S|sudo pacman -Syu|AUR_HELPER"? -S|makepkg -si|install_package_list )' |
    grep -vE 'pacman -Qq|pacman -Si|pacman-conf|^[0-9]+:install_package_list\(\)'
)

if ((${#package_ops[@]} < 8)); then
  fail "found ${#package_ops[@]} package operations in install.sh, which is fewer than there are"
else
  pass "found ${#package_ops[@]} package operations in install.sh"
fi

# Each has to carry one of the three: the literal flag, or one of the arrays
# that holds it. The arrays are how an --interactive run puts the questions
# back, so they count as confirming nothing by default.
unconfirmed=()
for op in "${package_ops[@]}"; do
  [[ $op == *'--noconfirm'* ]] && continue
  [[ $op == *'${CONFIRM[@]}'* ]] && continue
  [[ $op == *'${AUR_CONFIRM[@]}'* ]] && continue
  unconfirmed+=("${op%%:*}")
done
unconfirmed_str=""
((${#unconfirmed[@]} > 0)) && unconfirmed_str="$(printf '%s ' "${unconfirmed[@]}")"
check "no package operation stops to confirm, by line number" "$unconfirmed_str" ""

# Anti-vacuity. The check above passes for a file with no package operations at
# all, and would keep passing for a grep that had quietly stopped matching. A
# floor rather than the exact count, which says nothing about confirmations and
# would fail the day a package operation is added or removed.
pacman_ops="$(printf '%s\n' "${package_ops[@]}" | grep -c 'pacman')"
if ((pacman_ops < 6)); then
  fail "only $pacman_ops of them invoke pacman, so this is not reading install.sh"
else
  pass "$pacman_ops of them invoke pacman"
fi

# ---- --interactive puts them back -------------------------------------------
#
# install.sh cannot be sourced: it installs packages at the top level. The
# argument parsing is lifted out of the shipped file, so what runs below is
# what ships.

# Two pieces, because they sit apart in the file: the parsing is above the
# logging block, which truncates install.log, so --help cannot destroy the log
# of the failed install someone is looking at.
{
  sed -n '/^UNATTENDED=1$/,/^done$/p' "$INSTALL"
  sed -n '/^CONFIRM=()$/,/^fi$/p' "$INSTALL"
} >"$TMP/args.sh"
check "the argument parsing was lifted out of install.sh" \
  "$(grep -c -- '--interactive)' "$TMP/args.sh")" "1"
check "and it carries the flag array it sets" "$(grep -c 'CONFIRM=(--noconfirm)' "$TMP/args.sh")" "1"
check "and the parsing really does come before the log is truncated" \
  "$([[ $(grep -n '^UNATTENDED=1$' "$INSTALL" | cut -d: -f1) -lt $(grep -n '^: >"\$INSTALL_LOG"$' "$INSTALL" | cut -d: -f1) ]] && echo before || echo after)" \
  "before"

cat >>"$TMP/args.sh" <<'TAILEOF'
printf 'unattended=%s flags=%s\n' "$UNATTENDED" "${CONFIRM[*]}"
TAILEOF

parse() {
  RED='' YELLOW='' NC='' "$BASH_BIN" "$TMP/args.sh" "$@" >"$TMP/out" 2>&1
  printf '%s' "$?" >"$TMP/rc"
}

parse
check "a plain install is unattended" "$(grep -c 'unattended=1 flags=--noconfirm' "$TMP/out")" "1"
check "and says so, so it is not a surprise" \
  "$(grep -c 'Installing without confirmations' "$TMP/out")" "1"
check "and exits 0" "$(cat "$TMP/rc")" "0"

parse --interactive
check "--interactive confirms every operation" "$(grep -c 'unattended=0 flags=$' "$TMP/out")" "1"
check "and does not announce an unattended run" \
  "$(grep -c 'Installing without confirmations' "$TMP/out")" "0"

parse --help
check "--help explains both" "$(grep -c 'interactive' "$TMP/out")" "2"
check "and exits 0" "$(cat "$TMP/rc")" "0"

parse --unattended
check "an option that does not exist stops rather than being ignored" \
  "$(cat "$TMP/rc")" "1"
check "and names it" "$(grep -c 'Unknown option: --unattended' "$TMP/out")" "1"

# ---- the password, once -----------------------------------------------------

sed -n '/^SUDO_KEEPALIVE_PID=""$/,/^SUDO_KEEPALIVE_PID=\$!$/p' "$INSTALL" >"$TMP/sudo.sh"
check "the sudo block was lifted out of install.sh" \
  "$(grep -c 'if ! sudo -v; then' "$TMP/sudo.sh")" "1"
check "and it ends with the keep-alive it starts" \
  "$(grep -c 'SUDO_KEEPALIVE_PID=\$!' "$TMP/sudo.sh")" "1"

cat >>"$TMP/sudo.sh" <<'TAILEOF'
printf '%s' "$SUDO_KEEPALIVE_PID" >"$KEEPALIVE_PID"
TAILEOF

# A sudo that logs how it was called. The mode file decides whether the
# cached-credential probe succeeds, whether the prompt succeeds, or neither.
STUB="$TMP/stub"
mkdir -p "$STUB"
cat >"$STUB/sudo" <<'SUDOEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$SUDO_LOG"
mode="$(cat "$SUDO_MODE")"
case "$1" in
-n) [[ $mode == cached ]] ;;
-v) [[ $mode != refuses ]] ;;
*) true ;;
esac
SUDOEOF
chmod +x "$STUB/sudo"
for tool in sleep kill cat; do
  [[ -e /usr/bin/$tool ]] && ln -sf "/usr/bin/$tool" "$STUB/$tool"
done

run_sudo_block() {
  printf '%s' "$1" >"$TMP/mode"
  : >"$TMP/sudocalls"
  : >"$TMP/keepalive"
  SUDO_LOG="$TMP/sudocalls" SUDO_MODE="$TMP/mode" KEEPALIVE_PID="$TMP/keepalive" \
    RED='' YELLOW='' NC='' PATH="$STUB" \
    "$BASH_BIN" "$TMP/sudo.sh" >"$TMP/out" 2>&1 </dev/null
  printf '%s' "$?" >"$TMP/rc"
}

run_sudo_block cached
check "a cached credential is reused without a prompt" \
  "$(grep -c -- '-v' "$TMP/sudocalls")" "0"
check "and the probe that decided it does not prompt either" \
  "$(grep -c -- '-n true' "$TMP/sudocalls")" "1"
check "and nothing is said about a password" \
  "$(grep -c 'asked once' "$TMP/out")" "0"

run_sudo_block prompts
check "with no cached credential it asks, once" \
  "$(grep -c -- '-v' "$TMP/sudocalls")" "1"
check "and says the asking is over" "$(grep -c 'asked once, now' "$TMP/out")" "1"
check "and carries on" "$(cat "$TMP/rc")" "0"

run_sudo_block refuses
check "a machine that cannot authenticate stops" \
  "$([[ $(cat "$TMP/rc") != "0" ]] && echo stopped || echo continued)" "stopped"
check "before installing anything" "$(grep -c 'nothing was installed' "$TMP/out")" "1"

# The keep-alive must not outlive the install. A refresher left running is a
# machine that stays sudo-authorised after the script that needed it is gone.
run_sudo_block cached
keepalive="$(cat "$TMP/keepalive")"
if [[ ! $keepalive =~ ^[0-9]+$ ]]; then
  fail "the keep-alive recorded no pid, so this check is testing nothing"
else
  pass "the keep-alive recorded its pid, $keepalive"
  # The pid is the recorded one, never a pattern: pkill -f matches the shell
  # running this suite as readily as the loop it is aimed at.
  check "and it is gone once the script that started it has exited" \
    "$(kill -0 "$keepalive" 2>/dev/null && echo running || echo gone)" "gone"
fi

check "the trap that kills it is on EXIT, so it runs on failure too" \
  "$(sed 's/^[[:space:]]*#.*//' "$INSTALL" | grep -c 'trap stop_sudo_keepalive EXIT')" "1"
check "and it kills a recorded pid rather than matching a pattern" \
  "$(sed 's/^[[:space:]]*#.*//' "$INSTALL" | grep -c 'pkill')" "0"

# ---- the AUR helper is told to stop asking too -------------------------------
#
# --noconfirm alone is not enough. paru opens each PKGBUILD for review and yay
# asks about diffs and edits, and both wait for a keypress.

# shellcheck source=/dev/null
source "$REPO/.local/bin/hyprsimple-aur-helper.sh"
check "paru is told to skip the review" \
  "$(aur_unattended_flags paru | grep -c -- '--skipreview')" "1"
check "and yay to answer its own questions" \
  "$(aur_unattended_flags yay | grep -c -- '--answerdiff=None')" "1"
check "and both are told not to confirm" \
  "$( { aur_unattended_flags paru; aur_unattended_flags yay; } | grep -c -- '--noconfirm')" "2"
check "and a helper this project does not know still gets the one flag it can" \
  "$(aur_unattended_flags something-else)" "--noconfirm"

# One flag per line. Building a string and splitting on spaces breaks the first
# time a flag needs one.
check "the flags come back one per line, for mapfile" \
  "$(aur_unattended_flags yay | wc -l | tr -d ' ')" "4"

# ---- what is still asked, and only at the end -------------------------------
#
# The logout prompt is the last line of the installer, after everything is
# installed, so leaving it there does not make anyone wait on the install. It
# is checked here so that it stays the only one.
mapfile -t prompts < <(sed 's/^[[:space:]]*#.*//' "$INSTALL" | grep -n 'read -rp')
check "install.sh has three prompts left, and no more" "${#prompts[@]}" "3"
check "the closing logout, which is the last line and blocks nothing" \
  "$(printf '%s\n' "${prompts[@]}" | grep -c 'Logout to take effect')" "1"
check "the AUR choice, which an unattended run never reaches" \
  "$(printf '%s\n' "${prompts[@]}" | grep -c 'Install which one')" "1"
check "and the uncommitted-changes one, which only a checkout being worked on hits" \
  "$(printf '%s\n' "${prompts[@]}" | grep -c 'Continue and install HEAD')" "1"

# ---- documented -------------------------------------------------------------

# A floor on each. Pinning the exact count would fail whenever a paragraph is
# rewrapped, which says nothing about whether the flag is documented.
for doc in README.md FAQ.md; do
  mentions="$(grep -c -- '--interactive' "$REPO/$doc")"
  if ((mentions < 1)); then
    fail "$doc does not mention --interactive, so the flag is undocumented"
  else
    pass "$doc documents --interactive"
  fi
done
check "and the README says the password is asked for once" \
  "$(grep -c 'sudo password once' "$REPO/README.md")" "1"
check "and the FAQ says what an unattended upgrade gives up" \
  "$(grep -c 'including which packages to replace' "$REPO/FAQ.md")" "1"

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
