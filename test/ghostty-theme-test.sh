#!/bin/bash
# A theme switch rewrites ghostty's colour lines, and it only recognised one of
# the several spellings ghostty accepts.
#
# theme-switcher.sh filtered with
#
#   grep -vE '^(background|foreground|...|palette|theme) ='
#
# which requires exactly "key = ". ghostty accepts more than that, checked with
# `ghostty +validate-config`: key=value, key  =  value and leading whitespace
# all validate. So a line written any of those ways survived every switch:
#
#   theme=gruvbox        kept, and "theme = kanagawa" appended after it
#
# The header of the shipped ghostty config promises these lines are "removed
# and rewritten from the active theme", so someone who set their own theme was
# told it would be replaced, and instead kept a dead line they could no longer
# see taking effect.
#
# Nothing here runs ghostty as a terminal or touches the real ~/.config. The
# switcher runs against a temporary home with every tool it calls stubbed.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the premise: ghostty really does accept these spellings -----------------
#
# If it did not, there would be no bug and every check below would be about
# nothing.
if ! command -v ghostty >/dev/null 2>&1; then
  pass "ghostty is not installed here, so its verdict is skipped"
else
  accepts() {
    printf '%s\n' "$1" >"$TMP/probe.conf"
    ghostty +validate-config --config-file="$TMP/probe.conf" >/dev/null 2>&1 && echo yes || echo no
  }
  check "ghostty accepts key = value" "$(accepts 'font-size = 12')" "yes"
  check "and key=value with no spaces" "$(accepts 'font-size=12')" "yes"
  check "and padding around the equals" "$(accepts 'font-size   =   12')" "yes"
  check "and a leading tab" "$(accepts '	font-size = 12')" "yes"
fi

# --- the switch ---------------------------------------------------------------

STUB="$TMP/bin"; mkdir -p "$STUB"
for tool in gsettings hyprctl systemctl pkill busctl notify-send \
  hyprsimple-restart-waybar.sh hyprsimple-restart-dunst.sh; do
  printf '#!/bin/bash\nexit 0\n' >"$STUB/$tool"; chmod +x "$STUB/$tool"
done

HOME_DIR="$TMP/home"
GCONF="$HOME_DIR/.config/ghostty/config"

setup_home() {
  rm -rf "${TMP:?}/home"
  mkdir -p "$HOME_DIR/.local/bin" "$HOME_DIR/.cache" \
    "$HOME_DIR/.config/ghostty" "$HOME_DIR/.config/hypr/themes/demo"
  cp "$BIN/theme-switcher.sh" "$BIN/hypr-helpers.sh" "$BIN/theme-apply-templates.sh" \
    "$HOME_DIR/.local/bin/"
  # A theme naming a built-in ghostty theme, which is the branch that appends
  # a single "theme = " line.
  printf 'Demo Theme\n' >"$HOME_DIR/.config/hypr/themes/demo/ghostty-theme"
  # And a theme file of that name inside the fake config, so the validation at
  # the end judges the rewrite rather than the fixture. ghostty exits 1 on a
  # theme it cannot find, which is what a made-up name did the first time this
  # ran.
  mkdir -p "$HOME_DIR/.config/ghostty/themes"
  printf 'background = #1e1e2e\nforeground = #cdd6f4\n' \
    >"$HOME_DIR/.config/ghostty/themes/Demo Theme"
  # Every spelling ghostty accepts, plus two settings that must survive.
  cat >"$GCONF" <<'CFG'
font-size=12
theme=gruvbox
palette=0=#111111
  theme = indented
background   =   #000000
	foreground=#ffffff
keybind = ctrl+shift+t=new_tab
CFG
}
switch() {
  HOME="$HOME_DIR" THEME_SWITCHER_NO_RELOAD=1 PATH="$STUB:/usr/bin:/bin" \
    bash "$HOME_DIR/.local/bin/theme-switcher.sh" demo >/dev/null 2>&1
}
count() { grep -cE "$1" "$GCONF"; }

setup_home
switch

check "one theme line remains after a switch" \
  "$(count '^[[:space:]]*theme[[:space:]]*=')" "1"
check "and it is the one the theme asked for" \
  "$(count '^theme = Demo Theme$')" "1"
check "a theme written with no spaces is removed" \
  "$(count 'gruvbox')" "0"
check "and an indented one" "$(count 'indented')" "0"
check "a palette written with no spaces is removed" \
  "$(count '^[[:space:]]*palette[[:space:]]*=')" "0"
check "a padded background is removed" \
  "$(count '^[[:space:]]*background[[:space:]]*=')" "0"
check "and a tab indented foreground" \
  "$(count '^[[:space:]]*foreground[[:space:]]*=')" "0"

# The point of filtering rather than truncating: everything else is kept.
check "the user's font-size survives" "$(count '^font-size=12$')" "1"
check "and their keybind" "$(count 'keybind = ctrl\+shift\+t')" "1"

# Switching repeatedly must not grow the file.
before=$(wc -l <"$GCONF")
switch; switch
check "switching twice more does not add lines" "$(wc -l <"$GCONF")" "$before"
check "and still leaves exactly one theme line" \
  "$(count '^[[:space:]]*theme[[:space:]]*=')" "1"

# And the result is still a config ghostty accepts.
if command -v ghostty >/dev/null 2>&1; then
  # XDG_CONFIG_HOME, not HOME. ghostty resolves a theme against
  # $XDG_CONFIG_HOME/ghostty/themes and ignores HOME for it, so pointing HOME
  # at the fixture left it looking in the real one and failing.
  XDG_CONFIG_HOME="$HOME_DIR/.config" ghostty +validate-config --config-file="$GCONF" >/dev/null 2>&1
  check "the rewritten config still validates" "$?" "0"
  # And the check can fail: a config naming a theme that is not there does not
  # validate, which is what makes the one above worth running.
  printf 'theme = No Such Theme\n' >"$TMP/bad.conf"
  XDG_CONFIG_HOME="$HOME_DIR/.config" ghostty +validate-config --config-file="$TMP/bad.conf" >/dev/null 2>&1
  check "and validation does reject a missing theme, so that means something" "$?" "1"
fi

# --- the shipped config's promise matches what the filter does ---------------
#
# The header names the keys it says are rewritten. If the two lists drift, the
# file is lying to whoever reads it.

SHIPPED="$REPO/.config/ghostty/config"
SWITCHER="$BIN/theme-switcher.sh"
filter_keys=$(grep -oE '\(background\|[a-z|-]+\)' "$SWITCHER" | head -1 |
  tr -d '()' | tr '|' '\n' | LC_ALL=C sort -u | tr '\n' ' ')
if [[ -z ${filter_keys// /} ]]; then
  fail "could not read the key list out of theme-switcher.sh"
else
  pass "the filter names: $filter_keys"
fi

missing=()
for key in $filter_keys; do
  grep -q -- "$key" "$SHIPPED" || missing+=("$key")
done
missing_str=""
(( ${#missing[@]} > 0 )) && missing_str="$(printf '%s ' "${missing[@]}")"
check "and the shipped config's header mentions every one of them" "$missing_str" ""

# Both directions. The check above only requires the filter's keys to appear in
# the header, so dropping one from the filter satisfied it and the header went
# on promising a line nothing rewrote any more. Sabotage found that: removing
# cursor-text produced no failure at all.
#
# The list is written out, so changing what the switcher rewrites means
# changing this line and the header together, which is the point.
check "the filter rewrites exactly the keys the header names" \
  "$filter_keys" \
  "background cursor-color cursor-text foreground palette selection-background selection-foreground theme "

# The pattern has to be the tolerant one, stated by name so a narrowing edit is
# caught even if a fixture stops covering it.
check "the filter allows whitespace before the key" \
  "$(grep -c "grep -vE '\^\[\[:space:\]\]\*(" "$SWITCHER")" "1"
check "and around the equals" \
  "$(grep -c 'theme)\[\[:space:\]\]\*=' "$SWITCHER")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
