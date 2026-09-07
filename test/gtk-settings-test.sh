#!/bin/bash
# Checks that a theme switch writes gtk-theme-name into settings.ini, and that
# the migration writes the file for installs that never had one.
#
# theme-switcher.sh has always ended with
#
#   mkdir -p "$gtk_dir"
#   [[ -f "$gtk_dir/settings.ini" ]] && sed -i "s/^gtk-theme-name=.*/.../"
#
# under a comment saying some apps read these instead of gsettings. Nothing in
# hyprsimple has ever created settings.ini, so the mkdir made the directory,
# the test then failed, and the block wrote nothing on every theme switch.
# Measured on a live install that had switched themes many times:
# ~/.config/gtk-3.0 and ~/.config/gtk-4.0 both present and both empty.
#
# Nothing here touches the real ~/.config and no rofi is reachable.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"
SWITCHER="$BIN/theme-switcher.sh"
MIGRATION="$REPO/migrations/1788793000.sh"
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

# ---- the writer, taken out of the shipped script ---------------------------
#
# Extracted rather than copied, so these exercise what ships. If the function
# is renamed or removed the extraction comes up empty and says so.
FUNC="$TMP/set_gtk_theme_name.sh"
awk '/^set_gtk_theme_name\(\) \{/,/^\}$/' "$SWITCHER" >"$FUNC"
if ! grep -q '^set_gtk_theme_name() {' "$FUNC" || ! grep -q '^}$' "$FUNC"; then
  fail "could not read set_gtk_theme_name out of theme-switcher.sh"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "read set_gtk_theme_name out of theme-switcher.sh"
# shellcheck source=/dev/null
source "$FUNC"

W="$TMP/work"; mkdir -p "$W"

# absent
set_gtk_theme_name "$W/absent.ini" Adwaita-dark
check "an absent settings.ini is created" \
  "$([[ -f $W/absent.ini ]] && echo written || echo missing)" "written"
check "with a [Settings] header" "$(grep -c '^\[Settings\]$' "$W/absent.ini")" "1"
check "and the theme name under it" \
  "$(grep -c '^gtk-theme-name=Adwaita-dark$' "$W/absent.ini")" "1"

# key already there
printf '[Settings]\ngtk-font-name=Sans 11\ngtk-theme-name=Old\ngtk-cursor-theme-name=Bibata\n' \
  >"$W/haskey.ini"
set_gtk_theme_name "$W/haskey.ini" Adwaita
check "an existing key is replaced" "$(grep -c '^gtk-theme-name=Adwaita$' "$W/haskey.ini")" "1"
check "and not duplicated" "$(grep -c '^gtk-theme-name=' "$W/haskey.ini")" "1"
check "and the user's other settings are kept" \
  "$(grep -c -e '^gtk-font-name=Sans 11$' -e '^gtk-cursor-theme-name=Bibata$' "$W/haskey.ini")" "2"

# [Settings] present, key absent
printf '[Settings]\ngtk-font-name=Sans 11\n' >"$W/nokey.ini"
set_gtk_theme_name "$W/nokey.ini" Adwaita-dark
check "a file with [Settings] and no key gains one" \
  "$(grep -c '^gtk-theme-name=Adwaita-dark$' "$W/nokey.ini")" "1"
check "and keeps what was there" "$(grep -c '^gtk-font-name=Sans 11$' "$W/nokey.ini")" "1"

# no [Settings] at all
printf '# my notes\n' >"$W/nosection.ini"
set_gtk_theme_name "$W/nosection.ini" Adwaita-dark
check "a file with no [Settings] gains the section" \
  "$(grep -c '^\[Settings\]$' "$W/nosection.ini")" "1"
check "and the key" "$(grep -c '^gtk-theme-name=Adwaita-dark$' "$W/nosection.ini")" "1"
check "and the user's line survives" "$(grep -c '^# my notes$' "$W/nosection.ini")" "1"

# A key under a different section is not the one GTK reads, and is not ours.
#
# The first version of this function matched ^gtk-theme-name= anywhere, so it
# rewrote the one under [Other] and left [Settings] without a key. That is the
# same unanchored-match mistake theme-switcher.sh had in its rofi rewrite.
printf '[Settings]\ngtk-font-name=Sans\n\n[Other]\ngtk-theme-name=Wrong\n' >"$W/sections.ini"
set_gtk_theme_name "$W/sections.ini" Adwaita-dark
check "a key under another section is left alone" \
  "$(grep -c '^gtk-theme-name=Wrong$' "$W/sections.ini")" "1"
check "and [Settings] gets its own" \
  "$(awk '/^\[Settings\]/{s=1;next} /^\[/{s=0} s && /^gtk-theme-name=Adwaita-dark$/{n++} END{print n+0}' "$W/sections.ini")" "1"

# Running twice must not stack lines up.
set_gtk_theme_name "$W/nokey.ini" Adwaita
set_gtk_theme_name "$W/nokey.ini" Adwaita-dark
check "switching themes repeatedly leaves exactly one key" \
  "$(grep -c '^gtk-theme-name=' "$W/nokey.ini")" "1"
check "holding the last value asked for" \
  "$(grep -c '^gtk-theme-name=Adwaita-dark$' "$W/nokey.ini")" "1"

# ---- the caller really uses it ---------------------------------------------
#
# Comments stripped, because the block explains the old shape in one.
code() { sed 's/#.*//' "$1"; }
check "theme-switcher.sh calls it for both GTK directories" \
  "$(code "$SWITCHER" | grep -c 'set_gtk_theme_name "\$gtk_dir/settings.ini"')" "1"
check "inside a loop over gtk-3.0 and gtk-4.0" \
  "$(code "$SWITCHER" | grep -c 'for gtk_dir in .*gtk-3.0.*gtk-4.0')" "1"
check "and no longer skips the file when it is absent" \
  "$(code "$SWITCHER" | grep -c 'if \[\[ -f "\$gtk_dir/settings.ini" \]\]')" "0"

# ---- the migration ---------------------------------------------------------

STUB="$TMP/bin"; mkdir -p "$STUB"
# A heredoc, not a printf. Building this stub with nested printf quoting ate
# the %s and wrote a script that printed an empty line, so the migration read
# no theme and four checks failed for a reason that had nothing to do with it.
cat >"$STUB/gsettings" <<'STUBEOF'
#!/bin/bash
echo "'Adwaita-dark'"
STUBEOF
chmod +x "$STUB/gsettings"

# A rofi of its own, ahead of the real one. This suite only greps
# theme-switcher.sh rather than running it, so nothing here reaches a picker
# today, but the stub directory below is what would be in front if that ever
# changed. suite-hygiene-test.sh requires it of any suite that names a
# picker-capable script, and being conservative there costs one line.
printf '#!/bin/bash\nexit 1\n' >"$STUB/rofi"
chmod +x "$STUB/rofi"

run_migration() {
  HOME="$1" PATH="$STUB:/usr/bin:/bin" bash "$MIGRATION" >"$TMP/out" 2>&1
}

h1="$TMP/h1"; mkdir -p "$h1"
run_migration "$h1"
check "the migration writes gtk-3.0/settings.ini when it is absent" \
  "$(grep -c '^gtk-theme-name=Adwaita-dark$' "$h1/.config/gtk-3.0/settings.ini" 2>/dev/null)" "1"
check "and gtk-4.0" \
  "$(grep -c '^gtk-theme-name=Adwaita-dark$' "$h1/.config/gtk-4.0/settings.ini" 2>/dev/null)" "1"
check "and says how many it wrote" "$(grep -c 'Wrote 2 settings.ini' "$TMP/out")" "1"

run_migration "$h1"
check "running it again writes nothing" "$(grep -c 'already exist' "$TMP/out")" "1"

h2="$TMP/h2"; mkdir -p "$h2/.config/gtk-3.0" "$h2/.config/gtk-4.0"
printf '[Settings]\ngtk-font-name=Mine\n' >"$h2/.config/gtk-3.0/settings.ini"
printf '[Settings]\ngtk-font-name=Mine\n' >"$h2/.config/gtk-4.0/settings.ini"
run_migration "$h2"
check "an existing settings.ini is not rewritten by the migration" \
  "$(cat "$h2/.config/gtk-3.0/settings.ini")" "$(printf '[Settings]\ngtk-font-name=Mine')"

# gsettings unreachable: write nothing rather than a made up theme name.
cat >"$STUB/gsettings" <<'STUBEOF'
#!/bin/bash
exit 1
STUBEOF
chmod +x "$STUB/gsettings"
h3="$TMP/h3"; mkdir -p "$h3"
run_migration "$h3"
check "with no readable GTK theme, nothing is written" \
  "$([[ -e $h3/.config/gtk-3.0/settings.ini ]] && echo written || echo none)" "none"
check "and the migration says why" \
  "$(grep -c 'Could not read the current GTK theme' "$TMP/out")" "1"

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
