#!/bin/bash
# Checks that hyprsimple-update names the configs an update changed which the
# user still holds their own version of. Never touches the real install.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$REPO/.local/bin/hyprsimple-update.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'not ok - refusing to operate outside the fixture: %s\n' "${1:-<empty>}" >&2
    exit 1
  fi
}

# The update restarts things and installs packages. Stubbing these keeps the
# suite off the running session and off the network. pgrep exits 1 so the
# reload block is skipped rather than half executed.
STUB="$TMP/stub"
mkdir -p "$STUB"
for c in pgrep hyprctl pacman yay sudo systemctl; do
  printf '#!/bin/sh\nexit 1\n' >"$STUB/$c"
  chmod +x "$STUB/$c"
done
printf '#!/bin/sh\nexit 0\n' >"$STUB/hyprsimple-migrate.sh"
chmod +x "$STUB/hyprsimple-migrate.sh"

ORIGIN="$TMP/origin.git"
# -b main explicitly: a bare repo takes its HEAD from the runner's
# init.defaultBranch, which is master on the CI image and main here. A mismatch
# makes every clone come out empty with only a warning on stderr, which is how
# four of these checks once passed against an install that did not exist.
git init -q --bare -b main "$ORIGIN" 2>/dev/null ||
  { git init -q --bare "$ORIGIN"; git -C "$ORIGIN" symbolic-ref HEAD refs/heads/main; }

# A minimal origin carrying one unsplittable config and the updater itself.
SEED="$TMP/seed"
must_be_fixture "$SEED"
mkdir -p "$SEED/.config" "$SEED/.local/bin"
git init -q "$SEED" && git -C "$SEED" config user.email t@e && git -C "$SEED" config user.name t
printf 'V1\n' >"$SEED/.config/starship.toml"
printf 'V1\n' >"$SEED/.config/untouched.toml"
cp "$UPDATE" "$SEED/.local/bin/hyprsimple-update.sh"
cp "$REPO/.local/bin/hyprsimple-refresh-config.sh" "$SEED/.local/bin/"
printf '0.0.1\n' >"$SEED/version"
git -C "$SEED" add -A && git -C "$SEED" commit -qm v1
git -C "$SEED" branch -M main && git -C "$SEED" push -q "$ORIGIN" main

new_case() {
  CASE="$TMP/$1"
  must_be_fixture "$CASE"
  INSTALL="$CASE/install"
  FAKE_HOME="$CASE/home"
  git clone -q "file://$ORIGIN" "$INSTALL"
  # A fixture that did not clone must fail loudly. Every grep below returns 0
  # against an empty install, so without this the suite reports success for
  # checks it never actually ran.
  if [[ ! -f $INSTALL/.local/bin/hyprsimple-update.sh ]]; then
    printf 'not ok - fixture install did not clone (%s)\n' "$1" >&2
    exit 1
  fi
  mkdir -p "$FAKE_HOME/.config" "$FAKE_HOME/.local/bin"
  cp "$SEED/.local/bin/hyprsimple-refresh-config.sh" "$FAKE_HOME/.local/bin/"
  printf '#!/bin/sh\nexit 0\n' >"$FAKE_HOME/.local/bin/hyprsimple-migrate.sh"
  chmod +x "$FAKE_HOME/.local/bin/hyprsimple-migrate.sh"
}

ship() { # ship <path> <content>: publish a new version from the seed
  printf '%s\n' "$2" >"$SEED/$1"
  git -C "$SEED" add -A && git -C "$SEED" commit -qm "change $1"
  git -C "$SEED" push -q "$ORIGIN" main
}

run_update() {
  HOME="$FAKE_HOME" HYPRSIMPLE_PATH="$INSTALL" PATH="$STUB:$PATH" \
    bash "$INSTALL/.local/bin/hyprsimple-update.sh" >"$CASE/out" 2>&1
  printf '%s' "$?" >"$CASE/rc"
}

# --- 1. a changed config the user has their own version of is named --------

new_case reports
printf 'MINE\n' >"$FAKE_HOME/.config/starship.toml"
ship .config/starship.toml V2
run_update
check "a changed config the user diverged from is reported" \
  "$(grep -c 'refresh-config.sh starship.toml' "$CASE/out")" "1"

# --- 2. a config this update did not touch is not named -------------------

new_case untouched
printf 'MINE\n' >"$FAKE_HOME/.config/starship.toml"
printf 'MINE-TOO\n' >"$FAKE_HOME/.config/untouched.toml"
ship .config/starship.toml V3
run_update
check "a config this update did not change is not reported" \
  "$(grep -c 'untouched.toml' "$CASE/out")" "0"

# --- 3. a user whose copy matches the new shipped one is not nagged -------

new_case matching
ship .config/starship.toml V4
printf 'V4\n' >"$FAKE_HOME/.config/starship.toml"
run_update
check "a matching copy is not reported" \
  "$(grep -c 'refresh-config.sh starship.toml' "$CASE/out")" "0"

# --- 4. a config the user never had is not reported -----------------------

new_case absent
ship .config/starship.toml V5
run_update
check "a config the user does not have is not reported" \
  "$(grep -c 'refresh-config.sh starship.toml' "$CASE/out")" "0"

# --- 5. a symlinked config is managed elsewhere and is not drift ----------

new_case symlinked
ship .config/starship.toml V6
# The target must differ from the shipped file, or cmp filters it out and the
# symlink guard is never the reason it stays quiet.
printf 'SOMETHING-ELSE\n' >"$CASE/managed-elsewhere.toml"
ln -sfn "$CASE/managed-elsewhere.toml" "$FAKE_HOME/.config/starship.toml"
run_update
check "a symlinked config is not reported" \
  "$(grep -c 'refresh-config.sh starship.toml' "$CASE/out")" "0"

# --- 6. an update that pulls nothing new reports nothing ------------------

new_case nochange
printf 'MINE\n' >"$FAKE_HOME/.config/starship.toml"
run_update
check "an update with nothing to pull reports no drift" \
  "$(grep -c 'refresh-config.sh' "$CASE/out")" "0"
check "and still exits 0" "$(cat "$CASE/rc")" "0"

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
