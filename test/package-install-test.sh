#!/bin/bash
# install.sh installs packages in bulk, and a bulk transaction is all or
# nothing: one unresolvable name and pacman installs none of them. This suite
# pins the recovery, that a failed batch is retried package by package so the
# resolvable ones still land and every casualty reaches FAILED_PACKAGES.
# Never invokes pacman. The property under test is which commands get composed,
# not whether pacman works, and CI has neither root nor a network.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# install.sh cannot be sourced: it installs packages at the top level. Lifting
# the two functions under test keeps the suite hermetic.
sed -n '/^install_packages()/,/^}/p;/^install_package_list()/,/^}/p' \
  "$REPO/install.sh" >"$TMP/lifted.sh"
check "install_packages was lifted out of install.sh" \
  "$(grep -c '^install_packages()' "$TMP/lifted.sh")" "1"
check "install_package_list was lifted out of install.sh" \
  "$(grep -c '^install_package_list()' "$TMP/lifted.sh")" "1"

# The colour variables belong to install.sh's preamble, which is not lifted.
# shellcheck disable=SC2034  # read by the install.sh functions sourced below
YELLOW='' RED='' NC=''
# shellcheck disable=SC1091
. "$TMP/lifted.sh"

# A stub standing in for `sudo pacman -S`. It logs the package names it was
# given, logs its raw arguments separately so flag handling can be checked, and
# fails whenever the batch contains the poisoned name. That is how a real
# unresolvable package behaves: the whole transaction is refused.
stub() {
  local args=("$@") pkgs=() a
  for a in "${args[@]}"; do
    [[ $a == -* ]] || pkgs+=("$a")
  done
  printf '%s\n' "${pkgs[*]}" >>"$TMP/calls"
  printf '%s\n' "$*" >>"$TMP/raw"
  for a in "${pkgs[@]}"; do
    [[ $a == "poisoned" ]] && return 1
  done
  return 0
}

# --- 1. a poisoned batch still installs its survivors ----------------------

FAILED_PACKAGES=()
: >"$TMP/calls"; : >"$TMP/raw"
install_packages stub --noconfirm -- good-one poisoned good-two >/dev/null 2>&1

check "the bulk attempt ran once with the whole batch" \
  "$(grep -cx 'good-one poisoned good-two' "$TMP/calls")" "1"
check "good-one was retried on its own" \
  "$(grep -cx 'good-one' "$TMP/calls")" "1"
check "good-two was retried on its own" \
  "$(grep -cx 'good-two' "$TMP/calls")" "1"
check "only the poisoned package was recorded as failed" \
  "${FAILED_PACKAGES[*]}" "poisoned"

# --- 2. a clean batch does not trigger the retry ---------------------------

FAILED_PACKAGES=()
: >"$TMP/calls"; : >"$TMP/raw"
install_packages stub --noconfirm -- good-one good-two >/dev/null 2>&1

check "a clean batch installs in one call" \
  "$(wc -l <"$TMP/calls" | tr -d ' ')" "1"
check "a clean batch records no failures" \
  "${#FAILED_PACKAGES[@]}" "0"

# --- 3. the separator divides installer from packages ----------------------
#
# Without it the flags would be treated as package names, so the check is that
# the package log holds packages only.

FAILED_PACKAGES=()
: >"$TMP/calls"; : >"$TMP/raw"
install_packages stub --noconfirm -- good-one >/dev/null 2>&1

check "installer flags did not leak into the package list" \
  "$(grep -c -- '--noconfirm' "$TMP/calls")" "0"

# --- 4. a missing separator fails loudly -----------------------------------
#
# Without the separator every argument reads as part of the installer, so the
# package list comes out empty. Returning 0 there would report success having
# installed nothing, which is the failure this whole change exists to remove.

FAILED_PACKAGES=()
: >"$TMP/calls"; : >"$TMP/raw"
install_packages stub --noconfirm good-one >/dev/null 2>&1
check "a call with no -- separator returns non-zero" "$?" "1"
# Deliberately not also asserting that no installer ran. An empty package list
# returns early with or without the guard, so that check cannot discriminate:
# it stays green with the guard deleted, which makes it noise rather than a
# check. The exit status is the only part that actually moves.

# --- 5. the three raw call sites are gone ----------------------------------

check "no pacman install discards its result with || true" \
  "$(grep -cE 'sudo pacman -S .*\|\| true' "$REPO/install.sh")" "0"

# --- 6. the retry logic has one definition ---------------------------------
#
# The split exists so bulk-then-retry is written once. A second copy would pass
# every check above while reintroducing the drift this change removes.

check "the individual-retry loop is defined once" \
  "$(grep -c 'Retrying individually' "$REPO/install.sh")" "1"

# --- 7. the file wrapper stays interactive ---------------------------------
#
# packages.txt is installed with prompts today. The driver sites pass
# --noconfirm themselves, so nothing may add it to the bulk attempt on a
# caller's behalf. This is the check that would catch that regression, and
# nothing above it would.

FAILED_PACKAGES=()
: >"$TMP/calls"; : >"$TMP/raw"
printf '%s\n' '# a comment' '' 'good-one' 'good-two' >"$TMP/list.txt"
install_package_list "$TMP/list.txt" stub >/dev/null 2>&1

check "the file wrapper reads its packages past comments and blanks" \
  "$(grep -cx 'good-one good-two' "$TMP/calls")" "1"
check "the bulk attempt did not gain --noconfirm on the caller's behalf" \
  "$(grep -c -- '--noconfirm' "$TMP/raw")" "0"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
