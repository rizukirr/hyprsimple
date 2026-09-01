#!/bin/bash
# Checks the rofi import split: that every stub reaches its default, that a
# changed default is live without a migration, and that a stub override wins
# while the properties it does not mention keep tracking the default.
# Never touches the real ~/.config.

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

# Every fixture path goes through this before anything writes to it. An empty
# or unexpected path would make the writes below land in the real $HOME.
must_be_fixture() {
  if [[ -z ${1:-} || $1 != "$TMP"/* ]]; then
    printf 'not ok - refusing to operate outside the fixture: %s\n' "${1:-<empty>}" >&2
    exit 1
  fi
}

# rofi is not installed on the CI runner. The checks that need it are skipped
# there rather than silently passing, so a local run stays the stronger one.
HAVE_ROFI=0
command -v rofi >/dev/null 2>&1 && HAVE_ROFI=1

# --- build a fixture install and a fixture home -----------------------------

INSTALL="$TMP/install"
FAKE_HOME="$TMP/home"
must_be_fixture "$INSTALL"
must_be_fixture "$FAKE_HOME"
mkdir -p "$INSTALL" "$FAKE_HOME/.config"

# The install is the repo's tracked content, which is what install.sh copies in.
cp -r "$REPO/default" "$INSTALL/default"
mkdir -p "$INSTALL/.config"
cp -r "$REPO/.config/rofi" "$INSTALL/.config/rofi"

# What install.sh does for rofi: copy .config/rofi across, then link the
# defaults in beside it.
cp -r "$INSTALL/.config/rofi" "$FAKE_HOME/.config/rofi"
ln -sfn "$INSTALL/default/rofi" "$FAKE_HOME/.config/rofi/hyprsimple"

STUBS=(config.rasi confirm.rasi font.rasi keybindings/style.rasi theme-picker/style.rasi)

# --- 1. every stub's import target exists ----------------------------------
#
# This is the failure that would otherwise be silent: rofi logs nothing for a
# missing @import and renders unstyled instead of exiting non-zero.

for rel in "${STUBS[@]}"; do
  stub="$FAKE_HOME/.config/rofi/$rel"
  target=$(sed -n 's/^@import[[:space:]]*"\(.*\)"[[:space:]]*$/\1/p' "$stub" | head -1)
  check "stub $rel declares an import" "$([[ -n $target ]] && echo yes || echo no)" "yes"
  # The import must come first. rasi is later-wins, so anything above it is
  # silently overridden by the default, which is the one way a well-meaning
  # edit to a stub can fail without any error at all.
  check "stub $rel imports before anything else" \
    "$(sed -n '/^[[:space:]]*$/d; p' "$stub" | head -1 | grep -c '^@import')" "1"
  check "stub $rel import target exists" \
    "$([[ -f $FAKE_HOME/.config/rofi/$target ]] && echo yes || echo no)" "yes"
done

# The defaults keep their own relative imports, which resolve against
# ~/.config/rofi rather than the file doing the importing. rofi-colors.rasi is
# written there by theme-switcher.sh, so it is absent in a bare fixture and
# only the shape is checked here.
check "a default still imports the theme colours" \
  "$(grep -l 'rofi-colors.rasi' "$INSTALL/default/rofi/confirm.rasi" >/dev/null && echo yes || echo no)" "yes"

# --- 2. a changed default is live through the stub, with no migration -------

if [[ $HAVE_ROFI == 1 ]]; then
  # A property rofi knows. -dump-theme silently drops unknown custom
  # properties, so asserting on an invented one would pass against anything.
  printf 'window { width: 321px; }\n' >>"$INSTALL/default/rofi/theme-picker/style.rasi"
  got=$(cd "$FAKE_HOME/.config/rofi" && HOME="$FAKE_HOME" rofi -no-config -dump-theme \
    -theme "$FAKE_HOME/.config/rofi/theme-picker/style.rasi" 2>/dev/null |
    sed -n 's/^[[:space:]]*width:[[:space:]]*\([0-9]*\)px.*/\1/p' | head -1)
  check "a default changed in the install is live through the stub" "$got" "321"

  # --- 3. a stub override wins, and untouched properties still track ---------

  printf 'window { width: 999px; }\n' >>"$FAKE_HOME/.config/rofi/theme-picker/style.rasi"
  printf 'window { height: 654px; }\n' >>"$INSTALL/default/rofi/theme-picker/style.rasi"
  out=$(cd "$FAKE_HOME/.config/rofi" && HOME="$FAKE_HOME" rofi -no-config -dump-theme \
    -theme "$FAKE_HOME/.config/rofi/theme-picker/style.rasi" 2>/dev/null)
  check "the stub's own override wins over the default" \
    "$(sed -n 's/^[[:space:]]*width:[[:space:]]*\([0-9]*\)px.*/\1/p' <<<"$out" | head -1)" "999"
  check "a property the stub does not set still tracks the default" \
    "$(sed -n 's/^[[:space:]]*height:[[:space:]]*\([0-9]*\)px.*/\1/p' <<<"$out" | head -1)" "654"
else
  printf 'skip - rofi not installed, import resolution checks not run\n'
fi

# --- 4. the theme-owned paths are not part of the split --------------------

for rel in launcher powermenu; do
  check "$rel is left out of the split" \
    "$([[ -e $INSTALL/default/rofi/$rel ]] && echo present || echo absent)" "absent"
done

if [[ $failures -gt 0 ]]; then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
