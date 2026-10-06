#!/bin/bash
# The rule that hides a browser's screen-sharing bar hid ordinary windows too.
#
#   hl.window_rule({ match = { title = ".*is sharing.*" }, workspace = "special silent" })
#
# workspace is applied when a window opens, so any window whose title happened
# to contain those two words went straight to a hidden workspace and appeared
# not to open at all. Measured on a live session, with a terminal:
#
#   How Netflix is sharing your data -> ws=special:special
#
# The six titles a chromium browser gives that bar, read out of Brave's own
# locales/en-US.pak, are
#
#   $1 is sharing your screen.            $1 is sharing a window.
#   $1 is sharing your screen and audio.  $1 is sharing a window and audio.
#   $1 is sharing a Brave tab.            $1 is sharing a Brave tab and audio.
#
# so the object and the full stop are what separate the bar from prose.
#
# Nothing here opens a window. The pattern is read out of windows.lua and run
# against titles, which is the same question Hyprland asks of it.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RULES="$REPO/default/hypr/windows.lua"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# --- the pattern, taken from the rule -----------------------------------------
#
# Read from the file rather than repeated here, so a change to the rule is
# tested rather than shadowed by a copy that still says what it used to.
pattern=$(grep -oE 'title = "[^"]*is sharing[^"]*"' "$RULES" |
  head -1 | sed 's/^title = "//; s/"$//; s/\\\\\./\\./g')

if [[ -z $pattern ]]; then
  fail "no sharing rule found in windows.lua, so this suite is reading the wrong file"
  printf '\n1 check(s) failed\n' >&2
  exit 1
fi
pass "read the pattern: $pattern"

matches() { printf '%s' "$1" | grep -qE "$pattern" && echo yes || echo no; }

# --- every title the bar can actually have ------------------------------------

for title in \
  "meet.google.com is sharing your screen." \
  "meet.google.com is sharing your screen and audio." \
  "zoom.us is sharing a window." \
  "zoom.us is sharing a window and audio." \
  "app.slack.com is sharing a Brave tab." \
  "app.slack.com is sharing a Chrome tab and audio."; do
  check "hidden: $title" "$(matches "$title")" "yes"
done

# --- and the ordinary titles that used to be caught ---------------------------

for title in \
  "How Netflix is sharing your data" \
  "Alice is sharing a document" \
  "is sharing data with partners" \
  "Who is sharing my screen? - Reddit" \
  "A guide to sharing your screen" \
  "This tab is sharing your screen"; do
  check "left alone: $title" "$(matches "$title")" "no"
done

# --- the rule is still the one Hyprland will apply ---------------------------

# Comments stripped before counting. The rule now explains itself in a comment
# that quotes all six titles, and an unanchored grep counted those explanations
# as rules: eight, against the one that exists. Anchored to the start of the
# line so a lua `--` inside a string or an arithmetic minus survives, which is
# the mistake the lua stripper in another suite made once.
code_of() { sed 's/^[[:space:]]*--.*//' "$1"; }
CODE=$(code_of "$RULES")

check "the rule still sends the bar to a silent special workspace" \
  "$(printf '%s\n' "$CODE" | grep -c 'workspace = "special silent"')" "1"
check "and there is exactly one sharing rule, not two competing ones" \
  "$(printf '%s\n' "$CODE" | grep -c 'is sharing')" "1"
check "stripping comments leaves the rules behind" \
  "$(printf '%s\n' "$CODE" | grep -c '^hl\.window_rule(')" "$(grep -c '^hl\.window_rule(' "$RULES")"

# The old pattern must not come back. Stated by name, because a widening edit
# would still pass every check above.
check "the bare two-word pattern is gone" \
  "$(printf '%s\n' "$CODE" | grep -c 'title = ".\*is sharing.\*"')" "0"

# --- the emulator's popups open where Qt puts them ----------------------------
#
# The Android Emulator is a Qt app under XWayland, and Qt titles every popup
# with the application name. A combo box list is therefore a window of class
# "Emulator" and title "Emulator", the same pair the float rule matches. center
# is applied to override-redirect windows too, and it discards the position the
# app asked for. Measured on a live session, with a 276x70 override-redirect
# window asking for 100,100 on a 1920x1080 monitor under a 36px bar:
#
#   float = true   -> at 100,100
#   center = true  -> at 822,523
#
# so a rule on that pair may float, and may not centre.
#
# The file is run against a stub hl rather than grepped, so a rule reflowed
# over several lines is still seen. One run answers every question the checks
# below ask of the rules, as name and value on a line each.
FACTS=$(lua - "$RULES" <<'LUA'
local rules = {}
hl = {
  window_rule = function(rule) rules[#rules + 1] = rule end,
  layer_rule = function() end,
}
dofile(arg[1])

local function count(pred)
  local n = 0
  for _, rule in ipairs(rules) do
    if pred(rule, rule.match or {}) then n = n + 1 end
  end
  return n
end
local function jetbrains(match)
  return type(match.class) == "string" and match.class:find("jetbrains", 1, true) ~= nil
end
local function text(value)
  return type(value) == "table" and table.concat(value, " ") or tostring(value or "")
end

print("emulator_centred", count(function(rule, match)
  return rule.center and match.class == "^(Emulator)$"
end))
print("jetbrains_moved", count(function(rule, match)
  return jetbrains(match) and (rule.center or rule.min_size or rule.stay_focused or rule.no_focus)
end))
print("jetbrains_no_follow_mouse", count(function(rule, match)
  return jetbrains(match) and rule.no_follow_mouse
end))
print("portal_floats_whatever_the_title", count(function(rule, match)
  return match.class == "xdg-desktop-portal-gtk" and match.title == nil and rule.tag == "+floating-window"
end))
print("pip_moves", count(function(rule, match)
  return match.tag == "pip" and rule.move ~= nil
end))
print("pip_moves_by_window_w", count(function(rule, match)
  return match.tag == "pip" and text(rule.move):find("window_w", 1, true) ~= nil
end))
for _, rule in ipairs(rules) do
  local class = (rule.match or {}).class
  if rule.tag == "-default-opacity" and type(class) == "string" and class:find("youtube", 1, true) then
    print("webapp_pattern", class)
  end
  if rule.no_screen_share and rule.tag == "+floating-window" and type(class) == "string" then
    print("vault_pattern", class)
  end
end
LUA
)
fact() { printf '%s\n' "$FACTS" | awk -F'\t' -v name="$1" '$1 == name { print $2 }'; }

check "no rule centres the emulator's popups" "$(fact emulator_centred)" "0"

# --- a JetBrains popup opens where the IDE puts it ----------------------------
#
# The same mistake, wider. A rule matched every untitled floating window of a
# JetBrains IDE, centred it, held focus on it and forced it to at least half
# the monitor. Measured the same way, with class "jetbrains-studio" and an
# empty title:
#
#   asked for 276x70 at 100,100 -> 960x540 at 480,288
#
# Only the rule that stops focus following the mouse is kept, which is what the
# IDE needs and all it needs.
check "no rule moves, resizes or pins focus on a JetBrains window" "$(fact jetbrains_moved)" "0"
check "focus still does not follow the mouse into a JetBrains window" "$(fact jetbrains_no_follow_mouse)" "1"

# --- a browser's video app is opaque in every browser -------------------------
#
# A site installed as an app has the class <browser>-<site>__-<profile>. The
# rule that keeps YouTube and Zoom opaque named the chrome- form only, and
# hyprsimple ships Brave. Measured: class "brave-youtube.com__-Default" kept the
# default-opacity tag, and "chrome-youtube.com__-Default" lost it.
#
# Hyprland matches a class in full, which is what grep -x asks here.
webapp=$(fact webapp_pattern)
if [[ -z $webapp ]]; then
  fail "no rule keeps a YouTube app opaque, so this suite is reading the wrong file"
fi
webapp_matches() { printf '%s' "$1" | grep -qxE -- "$webapp" && echo yes || echo no; }

for class in \
  "brave-youtube.com__-Default" \
  "chrome-youtube.com__-Default" \
  "chromium-youtube.com__-Profile_1" \
  "brave-app.zoom.us__wc_home-Default" \
  "chrome-app.zoom.us__wc_home-Default"; do
  check "opaque: $class" "$(webapp_matches "$class")" "yes"
done

for class in \
  "brave-browser" \
  "chrome-mail.google.com__-Default" \
  "brave-youtubexcom__-Default"; do
  check "left alone: $class" "$(webapp_matches "$class")" "no"
done

# --- every portal dialog floats, whatever it is called ------------------------
#
# The portal only ever shows dialogs. The rule floated the ones whose title was
# on a list of English phrases, so a dialog titled anything else, or titled in
# another language, was tiled.
check "a portal window floats without its title being asked" \
  "$(fact portal_floats_whatever_the_title)" "1"

# --- picture in picture lands on the screen -----------------------------------
#
# The rules give the window a width of 600 and a position worked out from
# window_w. window_w is the width before the size rule applies. Measured with a
# window 276 wide on a 1920 monitor:
#
#   monitor_w-window_w-40 -> x 1604, right edge 2204, 284 off the screen
#   monitor_w-600-40      -> x 1280, right edge 1880
check "picture in picture is still moved to its corner" "$(fact pip_moves)" "1"
check "and not by a width it does not have yet" "$(fact pip_moves_by_window_w)" "0"

# --- a password manager stays out of a screen share ---------------------------
#
# Sharing the whole screen in a call shared an open password manager with it.
# Measured with a terminal full of text and a screenshot of its middle, which
# reads the screen the way a share does:
#
#   no rule                  9909 distinct colours, the text
#   no_screen_share = true   1 colour, black
#
# The same rule floats them, since a vault is something opened over the work
# and closed again.
mapfile -t vault_patterns < <(fact vault_pattern)
if (( ${#vault_patterns[@]} == 0 )); then
  fail "no rule keeps a password manager out of a screen share"
fi
vault_matches() {
  local pattern
  for pattern in "${vault_patterns[@]}"; do
    printf '%s' "$1" | grep -qxE -- "$pattern" && { echo yes; return; }
  done
  echo no
}

# 1Password 8.12 renamed its window class to the reverse-DNS form, and the
# third is the Bitwarden extension's own window in a chromium browser.
for class in \
  "1Password" \
  "1password" \
  "com.onepassword.OnePassword" \
  "Bitwarden" \
  "chrome-nngceckbapebfimnlniiiahkandclblb-Default" \
  "brave-nngceckbapebfimnlniiiahkandclblb-Profile_1"; do
  check "hidden from a share: $class" "$(vault_matches "$class")" "yes"
done

for class in \
  "brave-browser" \
  "com.mitchellh.ghostty" \
  "chrome-mail.google.com__-Default" \
  "Bitwarden-helper"; do
  check "left alone: $class" "$(vault_matches "$class")" "no"
done

# --- windows.lua still loads --------------------------------------------------

if command -v luac >/dev/null 2>&1; then
  if luac -p "$RULES" >/dev/null 2>&1; then
    pass "windows.lua still parses as lua"
  else
    fail "windows.lua no longer parses as lua"
  fi
else
  fail "luac is not installed, so windows.lua cannot be checked"
fi

# A rule file that had been emptied would pass everything above except this.
rules=$(grep -c '^hl\.\(window\|layer\)_rule(' "$RULES")
if (( rules >= 40 )); then
  pass "windows.lua still holds $rules rules"
else
  fail "windows.lua holds only $rules rules, which is too few to be intact"
fi

if (( failures > 0 )); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
