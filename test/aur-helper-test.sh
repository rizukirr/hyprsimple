#!/bin/bash
# Which AUR helper hyprsimple uses.
#
# install.sh, hyprsimple-update.sh and hyprsimple-muslimtify.sh each carried
# their own copy of the same ladder, and all three read yay first:
#
#   if command -v yay &>/dev/null; then AUR_HELPER="yay"
#   elif command -v paru &>/dev/null; then AUR_HELPER="paru"
#
# so a machine set up around paru was run through yay the moment yay appeared
# for any other reason, and the installer, finding neither, built yay without
# asking. Reported by a CachyOS user, where paru is what the distribution
# ships.
#
# Nothing here installs a package, contacts the AUR or runs pacman. Every
# acting command is a stub, and the helper detection itself needs no external
# command at all, so those checks run with a PATH holding only the stubs.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HELPER="$REPO/.local/bin/hyprsimple-aur-helper.sh"
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

check "the shared detection ships" "$([[ -r $HELPER ]] && echo present || echo missing)" "present"

# ---- a PATH holding exactly the helpers named ------------------------------
#
# Built fresh each time. A directory reused between cases would keep the
# previous case's helper on the PATH and every later check would read the same
# answer for the wrong reason.
#
# /usr/bin is deliberately not on the PATH these produce. The first version of
# this suite appended it so the lifted block could reach mktemp, and the
# maintainer's own paru sits there: every "with neither installed" case found
# it and passed for the wrong reason, and the two cases that build a helper
# built nothing and were reported as ok. Only the few real tools the lifted
# code needs are linked in, by name.
REAL_TOOLS=(mktemp rm)

stub_path() {
  local dir="$TMP/path.$RANDOM.$$"
  mkdir -p "$dir"
  local name tool
  for tool in "${REAL_TOOLS[@]}"; do
    ln -sf "$(command -v "$tool")" "$dir/$tool"
  done
  for name in "$@"; do
    printf '#!/bin/bash\nprintf %%s "%s"\n' "$name" >"$dir/$name"
    chmod +x "$dir/$name"
  done
  printf '%s' "$dir"
}

# bash is found through PATH, and these PATHs do not have it. Absolute, so the
# lifted blocks run under the same shell as this suite.
BASH_BIN="$(command -v bash)"

# Runs aur_helper with only the named helpers reachable. stdout, stderr and the
# exit status are kept apart, because the whole point of the return codes is
# that the caller can tell them apart.
#
# `set -u` on purpose: hyprsimple-muslimtify.sh runs under it, and a bare
# $HYPRSIMPLE_AUR_HELPER would abort there and nowhere else.
ask() {
  local override="$1"; shift
  local dir; dir="$(stub_path "$@")"
  local script="$TMP/ask.sh"
  cat >"$script" <<'ASKEOF'
set -u
source "$1"
aur_helper >"$2" 2>"$3"
exit $?
ASKEOF
  # Always set, empty when there is no override, because an empty value is
  # exactly what the helper has to treat as "not chosen".
  HYPRSIMPLE_AUR_HELPER="$override" PATH="$dir" \
    "$BASH_BIN" "$script" "$HELPER" "$TMP/out" "$TMP/err"
  printf '%s' "$?" >"$TMP/rc"
}

ask "" paru
check "with only paru installed, paru is used" "$(cat "$TMP/out")" "paru"
check "and it says so without complaint" "$(cat "$TMP/err")" ""
check "and reports success" "$(cat "$TMP/rc")" "0"

ask "" yay
check "with only yay installed, yay is used" "$(cat "$TMP/out")" "yay"

# The finding itself.
ask "" paru yay
check "with both installed, paru is used rather than yay" "$(cat "$TMP/out")" "paru"

ask "yay" paru yay
check "and HYPRSIMPLE_AUR_HELPER=yay picks yay back" "$(cat "$TMP/out")" "yay"
ask "paru" paru yay
check "and HYPRSIMPLE_AUR_HELPER=paru picks paru" "$(cat "$TMP/out")" "paru"

# An override naming something absent is its own answer, not "none installed".
# The installer builds a helper when it finds none, and doing that here would
# install a second helper beside the one that was asked for.
ask "nosuch" paru yay
check "an override naming an uninstalled helper fails" "$(cat "$TMP/rc")" "2"
check "and names it" "$(grep -c "nosuch" "$TMP/err")" "1"
check "and prints no helper to use" "$(cat "$TMP/out")" ""

ask "" # nothing installed at all
check "with neither installed, it reports none found" "$(cat "$TMP/rc")" "1"
check "and prints nothing" "$(cat "$TMP/out")" ""
check "and says nothing, leaving the message to the caller" "$(cat "$TMP/err")" ""

# Anti-vacuity. Every check above rests on the stub directory being what
# decides the answer, and a PATH that reached the real machine would make the
# "neither installed" case read whatever is really there.
dir_both="$(stub_path paru yay)"
check "the stub directory is what the answers come from" \
  "$(PATH="$dir_both" command -v paru)" "$dir_both/paru"

# ---- install.sh, lifted --------------------------------------------------
#
# install.sh cannot be sourced: it installs packages at the top level. The
# block under test is taken out of the shipped file rather than restated here,
# so a change to it is a change to what runs below.

sed -n '/^# Check for AUR helper$/,/^echo ""$/p' "$REPO/install.sh" >"$TMP/block.sh"
check "the AUR block was lifted out of install.sh" \
  "$(grep -c 'Using AUR helper' "$TMP/block.sh")" "1"
check "and it is the whole block, down to the build" \
  "$(grep -c 'makepkg' "$TMP/block.sh")" "1"

# Stubs for everything the build path would run. Each logs, none acts. The git
# one creates the directory it was asked to fetch into, because the block cds
# there afterwards and a stub that logged and did nothing would fail for a
# reason that has nothing to do with the choice being tested.
BUILD_STUBS="$TMP/buildstubs"
mkdir -p "$BUILD_STUBS"
cat >"$BUILD_STUBS/git" <<'GITEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$FETCH_LOG"
for arg; do :; done
mkdir -p "$arg"
GITEOF
cat >"$BUILD_STUBS/makepkg" <<'MPEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$BUILD_LOG"
MPEOF
cat >"$BUILD_STUBS/sudo" <<'SUDOEOF'
#!/bin/bash
printf '%s\n' "$*" >>"$PACMAN_LOG"
SUDOEOF
chmod +x "$BUILD_STUBS"/*

# Runs the lifted block with the named helpers present. mktemp, printf and the
# rest come from /usr/bin, so the stubs go in front of it rather than replacing
# it, and the helper names are stubbed there too.
# UNATTENDED is set by install.sh's argument parsing, above the lifted block,
# so the block cannot see it unless it is passed in. Defaulting it to 1 here
# matches a plain ./install.sh.
run_block() {
  local override="$1"; shift
  local unattended="${RUN_BLOCK_UNATTENDED:-1}"
  local dir; dir="$(stub_path "$@")"
  cp "$BUILD_STUBS"/* "$dir/"
  : >"$TMP/fetch"; : >"$TMP/build"; : >"$TMP/pacman"
  FETCH_LOG="$TMP/fetch" BUILD_LOG="$TMP/build" PACMAN_LOG="$TMP/pacman" \
    DOTFILES_DIR="$REPO" RED='' GREEN='' YELLOW='' NC='' \
    UNATTENDED="$unattended" \
    HYPRSIMPLE_AUR_HELPER="$override" PATH="$dir" \
    "$BASH_BIN" "$TMP/block.sh" >"$TMP/out" 2>&1 </dev/null
  printf '%s' "$?" >"$TMP/rc"
}

run_block "" paru
check "the installer uses an existing paru" "$(grep -c 'Using AUR helper: paru' "$TMP/out")" "1"
check "and builds nothing" "$(wc -l <"$TMP/build" | tr -d ' ')" "0"
check "and fetches nothing" "$(wc -l <"$TMP/fetch" | tr -d ' ')" "0"
check "and exits 0" "$(cat "$TMP/rc")" "0"

run_block "" yay
check "and an existing yay" "$(grep -c 'Using AUR helper: yay' "$TMP/out")" "1"
check "still building nothing" "$(wc -l <"$TMP/build" | tr -d ' ')" "0"

run_block "" paru yay
check "with both present the installer uses paru" \
  "$(grep -c 'Using AUR helper: paru' "$TMP/out")" "1"

run_block yay paru yay
check "and honours HYPRSIMPLE_AUR_HELPER" "$(grep -c 'Using AUR helper: yay' "$TMP/out")" "1"

run_block nosuch paru
check "an override naming nothing installed stops the install" \
  "$([[ $(cat "$TMP/rc") != "0" ]] && echo stopped || echo continued)" "stopped"
check "rather than quietly building a second helper" \
  "$(wc -l <"$TMP/build" | tr -d ' ')" "0"

# ---- with neither installed ------------------------------------------------

run_block ""
check "with neither installed the installer builds one" \
  "$(wc -l <"$TMP/build" | tr -d ' ')" "1"
check "and it is paru, not yay" "$(grep -c 'aur.archlinux.org/paru' "$TMP/fetch")" "1"
check "and yay is not fetched" "$(grep -c 'aur.archlinux.org/yay' "$TMP/fetch")" "0"
check "and it says which one it chose before doing it" \
  "$(grep -c 'Installing paru\.\.\.' "$TMP/out")" "1"
check "and reports paru as the helper in use" \
  "$(grep -c 'Using AUR helper: paru' "$TMP/out")" "1"

# The fetch used to go to a fixed /tmp/yay and skip the fetch entirely when
# that directory already existed, so a half-finished earlier run, or another
# user's directory of the same name, was built instead.
check "the build directory is not a fixed path in /tmp" \
  "$(sed 's/^[[:space:]]*#.*//' "$REPO/install.sh" | grep -c '/tmp/yay')" "0"
check "and is made fresh each time" "$(grep -c 'mktemp -d' "$TMP/block.sh")" "1"

# ---- the prompt ------------------------------------------------------------
#
# Only when a terminal is attached. Under curl-pipe stdin is the installer
# itself, and a read there consumes the next line of the script.
check "the prompt is guarded by a terminal check" \
  "$(grep -c -- '-t 0' "$TMP/block.sh")" "1"

SCRIPT_BIN="$(command -v script || true)"
if [[ -n $SCRIPT_BIN ]]; then
  run_on_pty() {
    local answer="$1"; shift
    local dir; dir="$(stub_path)"
    cp "$BUILD_STUBS"/* "$dir/"
    # script(1) linked in rather than its directory added to the PATH. Adding
    # /usr/bin back is what put the real paru in front of these cases again,
    # and each of them silently stopped testing the prompt.
    ln -sf "$SCRIPT_BIN" "$dir/script"
    : >"$TMP/fetch"; : >"$TMP/build"; : >"$TMP/pacman"
    printf '%s\n' "$answer" |
      FETCH_LOG="$TMP/fetch" BUILD_LOG="$TMP/build" PACMAN_LOG="$TMP/pacman" \
      DOTFILES_DIR="$REPO" RED='' GREEN='' YELLOW='' NC='' HYPRSIMPLE_AUR_HELPER='' \
      UNATTENDED=0 PATH="$dir" \
      "$SCRIPT_BIN" -qec "$BASH_BIN $TMP/block.sh" /dev/null >"$TMP/out" 2>&1
  }

  run_on_pty yay
  check "asked at an interactive terminal, an answer of yay builds yay" \
    "$(grep -c 'aur.archlinux.org/yay' "$TMP/fetch")" "1"
  check "and not paru" "$(grep -c 'aur.archlinux.org/paru' "$TMP/fetch")" "0"

  run_on_pty ""
  check "and an empty answer takes the default, paru" \
    "$(grep -c 'aur.archlinux.org/paru' "$TMP/fetch")" "1"

  run_on_pty "PARU"
  check "and the answer is read whatever its case" \
    "$(grep -c 'aur.archlinux.org/paru' "$TMP/fetch")" "1"

  run_on_pty "banana"
  check "an answer that is neither falls back to paru rather than stopping" \
    "$(grep -c 'aur.archlinux.org/paru' "$TMP/fetch")" "1"
  check "and says it did not understand" "$(grep -c 'Not paru or yay' "$TMP/out")" "1"
  # The default run does not ask at all, terminal or not. A prompt that only
  # a plain ./install.sh reaches is exactly the thing being removed here, and
  # the non-tty checks above cannot see it: they take the same branch for the
  # wrong reason.
  RUN_BLOCK_UNATTENDED=1
  dir="$(stub_path)"
  cp "$BUILD_STUBS"/* "$dir/"
  ln -sf "$SCRIPT_BIN" "$dir/script"
  : >"$TMP/fetch"; : >"$TMP/build"; : >"$TMP/pacman"
  printf 'yay\n' |
    FETCH_LOG="$TMP/fetch" BUILD_LOG="$TMP/build" PACMAN_LOG="$TMP/pacman" \
    DOTFILES_DIR="$REPO" RED='' GREEN='' YELLOW='' NC='' HYPRSIMPLE_AUR_HELPER='' \
    UNATTENDED=1 PATH="$dir" \
    "$SCRIPT_BIN" -qec "$BASH_BIN $TMP/block.sh" /dev/null >"$TMP/out" 2>&1
  check "an unattended run at a terminal does not stop to ask" \
    "$(grep -c 'Install which one' "$TMP/out")" "0"
  check "and builds paru, ignoring the answer nobody was asked for" \
    "$(grep -c 'aur.archlinux.org/paru' "$TMP/fetch")" "1"
else
  pass "skipped the prompt checks: no script(1) to give the block a terminal"
fi

# ---- hyprsimple-update.sh, lifted ------------------------------------------

sed -n '/^AUR_DETECT="\$HYPRSIMPLE_PATH/,/^fi$/p' \
  "$REPO/.local/bin/hyprsimple-update.sh" >"$TMP/update-block.sh"
check "the detection was lifted out of hyprsimple-update.sh" \
  "$(grep -c 'aur_helper' "$TMP/update-block.sh")" "1"
printf 'printf "%%s" "$AUR_HELPER"\n' >>"$TMP/update-block.sh"

update_picks() {
  local dir; dir="$(stub_path "$@")"
  PATH="$dir" HYPRSIMPLE_PATH="$REPO" HYPRSIMPLE_AUR_HELPER='' \
    "$BASH_BIN" "$TMP/update-block.sh" 2>/dev/null
}

check "the update uses an existing paru" "$(update_picks paru)" "paru"
check "and picks paru over yay" "$(update_picks paru yay)" "paru"
check "and leaves the helper empty when there is none" "$(update_picks)" ""

# An update that checks no AUR packages has to say so. Silence reads as an
# update that looked and found nothing to do.
check "and the update says when it skipped the AUR list" \
  "$(grep -c 'AUR packages were not checked' "$REPO/.local/bin/hyprsimple-update.sh")" "1"

# ---- nothing carries its own ladder any more -------------------------------
#
# The point of one detection is that there is one. Comments stripped, because
# the shared helper and two of its callers quote the old ladder in theirs.

offenders=()
for script in "$REPO/install.sh" "$REPO/.local/bin"/*.sh; do
  [[ $script == *hyprsimple-aur-helper.sh ]] && continue
  sed 's/^[[:space:]]*#.*//' "$script" | grep -qE 'command -v (yay|paru)' &&
    offenders+=("$(basename "$script")")
done
offenders_str=""
(( ${#offenders[@]} > 0 )) && offenders_str="$(printf '%s ' "${offenders[@]}")"
check "no script looks for a helper on its own" "$offenders_str" ""

users=0
for script in "$REPO/install.sh" "$REPO/.local/bin/hyprsimple-update.sh" \
  "$REPO/.local/bin/hyprsimple-muslimtify.sh"; do
  grep -q 'hyprsimple-aur-helper.sh' "$script" && users=$((users + 1))
done
check "and all three callers use the shared one" "$users" "3"

# It only reaches an installed machine if the delivery loops take it, and both
# of them take *.sh by glob rather than by name.
check "install.sh delivers .local/bin by glob, so the helper goes with it" \
  "$(grep -c '\.local/bin"/\*\.sh' "$REPO/install.sh")" "1"
check "and hyprsimple-update.sh refreshes it the same way" \
  "$(grep -c '\.local/bin"/\*\.sh' "$REPO/.local/bin/hyprsimple-update.sh")" "1"

# muslimtify stops rather than carrying on with pick_aur_helper undefined.
check "muslimtify stops when the shared detection is missing" \
  "$(grep -c 'missing helper: hyprsimple-aur-helper.sh' "$REPO/.local/bin/hyprsimple-muslimtify.sh")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
