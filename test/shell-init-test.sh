#!/bin/bash
# The three shell init files run in every shell their user opens, and two of
# them were checked by nothing at all. shellcheck cannot parse zsh, so zsh.sh is
# excluded from the lint step by name. fish.fish never even reached the list:
# the step globs *.sh, and a fish file does not end in .sh.
#
# So a syntax error in either would have shipped, and the symptom is quiet. A
# shell sources the file, hits the error, prints one line at login and skips the
# rest, leaving every alias below the error silently undefined.
#
# Each shell checks its own file with its own parser rather than by pattern
# matching, and the three are held to the same set of names so an alias added to
# one cannot silently skip the other two.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO/.local/bin"

failures=0
pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() {
  if [[ $2 == "$3" ]]; then pass "$1"
  else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi
}

# ---- each file parses, checked by the shell that will run it -------------
#
# Asserted rather than skipped when a shell is missing. A skip that fires on
# every run is a check that never runs, and this suite exists because two files
# were going unchecked.

if bash -n "$BIN/bashrc.sh" 2>/dev/null; then
  pass "bashrc.sh parses as bash"
else
  fail "bashrc.sh does not parse as bash"
fi

if command -v zsh >/dev/null 2>&1; then
  if zsh -n "$BIN/zsh.sh" 2>/dev/null; then
    pass "zsh.sh parses as zsh"
  else
    fail "zsh.sh does not parse as zsh"
  fi
else
  fail "zsh is not installed, so zsh.sh cannot be checked"
fi

if command -v fish >/dev/null 2>&1; then
  if fish --no-execute "$BIN/fish.fish" 2>/dev/null; then
    pass "fish.fish parses as fish"
  else
    fail "fish.fish does not parse as fish"
  fi
else
  fail "fish is not installed, so fish.fish cannot be checked"
fi

# ---- the three stay in step ----------------------------------------------

names_in() {
  case "$1" in
    *.fish)
      grep -oE "^(alias|abbr) [a-zA-Z0-9_.-]+|^function [a-zA-Z0-9_.-]+" "$1" |
        sed -E 's/^(alias|abbr|function) //'
      ;;
    *)
      grep -oE "^[[:space:]]*alias [a-zA-Z0-9_.-]+|^[a-zA-Z0-9_-]+\(\)" "$1" |
        sed -E 's/^[[:space:]]*alias //; s/\(\)$//'
      ;;
  esac | LC_ALL=C sort -u
}

bash_names="$(names_in "$BIN/bashrc.sh")"
zsh_names="$(names_in "$BIN/zsh.sh")"
fish_names="$(names_in "$BIN/fish.fish")"

check "the extractor found the commands bashrc.sh defines" \
  "$([[ $(printf '%s\n' "$bash_names" | grep -c .) -ge 10 ]] && echo enough || echo too-few)" "enough"

check "zsh.sh defines the same commands as bashrc.sh" \
  "$(comm -3 <(printf '%s\n' "$bash_names") <(printf '%s\n' "$zsh_names") | tr -d '[:space:]')" ""
check "fish.fish defines the same commands as bashrc.sh" \
  "$(comm -3 <(printf '%s\n' "$bash_names") <(printf '%s\n' "$fish_names") | tr -d '[:space:]')" ""

# ---- every alias points at a script that exists --------------------------

missing=()
while read -r target; do
  [[ -n $target ]] || continue
  [[ -f "$BIN/${target##*/}" ]] || missing+=("$target")
done < <(grep -hoE "\.local/bin/[a-zA-Z0-9_.-]+" \
  "$BIN/bashrc.sh" "$BIN/zsh.sh" "$BIN/fish.fish" | LC_ALL=C sort -u)

missing_str=""
(( ${#missing[@]} > 0 )) && missing_str="$(printf '%s ' "${missing[@]}")"
check "every alias target exists in .local/bin" "$missing_str" ""

# ---- and everything that target runs has to be installed ------------------
#
# "the alias target exists" is not the same as "the alias works". search.sh and
# search_by_keyword.sh, reached by `ffile` and `fany` in all three shells, both
# preview with bat, and nothing in packages.txt or aur-packages.txt installed it
# or pulled it in. Verified against the transitive closure of both lists: 633
# packages, and bat in none of them. Both aliases shipped with a dead preview
# pane on every install.
#
# The map is explicit rather than derived, because a command name and its
# package name agree only sometimes, and because pacman is not on the CI runner
# so nothing here can ask the system what provides what.

declare -A PROVIDED_BY=(
  [bat]=bat [fzf]=fzf [rg]=ripgrep [nvim]=neovim [lsd]=lsd [yazi]=yazi
  [zoxide]=zoxide [starship]=starship [jq]=jq [git]=git [lazygit]=lazygit
  [iw]=iw [notify-send]=libnotify [hyprctl]=hyprland
)

# nmcli is deliberately absent from that map. wifi.sh chooses its backend by
# which service is running and says so plainly when neither is, and hotspot.sh
# opens with `which nmcli >/dev/null 2>&1 || return 1`. NetworkManager is an
# optional backend here, not a missing dependency, and listing it would force
# one choice on machines already running iwd or networkd.

# Only the scripts an alias exposes. Those are the ones a user runs by name,
# and the ones where a missing dependency is a broken command rather than a
# degraded internal.
mapfile -t alias_targets < <(grep -hoE "\.local/bin/[a-zA-Z0-9_.-]+\.sh" \
  "$BIN/bashrc.sh" "$BIN/zsh.sh" "$BIN/fish.fish" | sed 's|.*/||' | LC_ALL=C sort -u)

if (( ${#alias_targets[@]} < 3 )); then
  fail "found ${#alias_targets[@]} alias targets, which is too few to be right"
else
  pass "checked ${#alias_targets[@]} scripts that an alias exposes"
fi

unlisted=()
found_any=0
for script in "${alias_targets[@]}"; do
  [[ -f $BIN/$script ]] || continue
  for cmd in "${!PROVIDED_BY[@]}"; do
    grep -qE "(^|[^a-zA-Z0-9_./-])$cmd([^a-zA-Z0-9_-]|$)" "$BIN/$script" || continue
    found_any=$((found_any + 1))
    pkg="${PROVIDED_BY[$cmd]}"
    grep -qxF "$pkg" "$REPO/packages.txt" "$REPO/aur-packages.txt" && continue
    unlisted+=("$script needs $cmd from $pkg")
  done
done

# A scan that matched nothing would pass this silently.
if (( found_any < 3 )); then
  fail "matched only $found_any known commands across those scripts, so the scan is not working"
else
  pass "matched $found_any known command uses to check"
fi

unlisted_str=""
(( ${#unlisted[@]} > 0 )) && unlisted_str="$(printf '%s; ' "${unlisted[@]}")"
check "every command an aliased script runs is in a package list" "$unlisted_str" ""

# ---- an alias must not change what a command means ------------------------
#
# All three shells carried
#
#   alias grep='rg --color=auto'
#
# and rg is not a drop in for grep. It does not claim to be. Its -r is
# --replace, not --recursive, so
#
#   grep -r hello .
#
# searched for the regex . and replaced every character it matched:
#
#   sub/a.txt:hellohellohellohellohellohellohello    exit 0
#
# rg also skips anything .gitignore excludes and every hidden file, so a plain
# grep inside a repository silently missed files grep would have found. Both
# failures look like results, which is the kind worth a check.
#
# Aliases are interactive only, so no script was affected. Every person typing
# grep at a prompt was.
#
# The fix is no alias, not a corrected one. grep is grep and rg is rg, so the
# checks below run grep through each shell's init file and require it to behave
# exactly as it does with no init file at all.

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP:?}"' EXIT

# A file inside a directory, which exercises -r, and gitignored, which is what
# rg declines to read.
PROBEHOME="$TMP/probehome"
mkdir -p "$PROBEHOME"

FIX="$TMP/fixture"
mkdir -p "$FIX/sub"
printf 'hello world\n' >"$FIX/sub/a.txt"
( cd "$FIX" && git init -q . && printf 'sub/\n' >.gitignore ) >/dev/null 2>&1

# Runs one grep through the shell's own init file, so the alias under test is
# the shipped text rather than a copy of it. The timeout is the check that a
# self-referential alias does not recurse forever.
#
# Written to a script and run from it, not passed to -c. A shell parses a -c
# string in one go, so an alias defined partway through it does not apply to a
# command already parsed on the same line, and the first version of this ran
# the real grep in bash and zsh no matter what the init file said. It passed
# against the rg alias, which is how it was caught. Aliases defined by an
# earlier line of a script do apply to later lines, so this measures the thing.
# fish runs the user's config.fish even for a script, and on a hyprsimple
# machine that sources the installed copy of the file under test. So the probe
# was reading the shipped file and the installed one at once, and while the
# shipped file still defined a grep alias it masked the installed one and the
# check passed on the overlap rather than on the repository. --no-config, and
# a home of its own for all three, which the suites are required to have
# anyway.
run_in_shell() {
  local shell="$1" body="$2"
  local script="$TMP/probe.$shell"
  {
    [[ $shell == bash ]] && printf 'shopt -s expand_aliases\n'
    printf 'source %q\n' "$3"
    printf '%s\n' "$body"
  } >"$script"
  case "$shell" in
    fish) HOME="$PROBEHOME" timeout 20 fish --no-config "$script" 2>/dev/null ;;
    *)    HOME="$PROBEHOME" timeout 20 "$shell" "$script" 2>/dev/null ;;
  esac
}

grep_through() {
  local init
  case "$1" in
    bash) init="$BIN/bashrc.sh" ;;
    zsh)  init="$BIN/zsh.sh" ;;
    fish) init="$BIN/fish.fish" ;;
  esac
  run_in_shell "$1" "cd $(printf '%q' "$FIX"); grep -r hello . --exclude-dir=.git" "$init"
}

# The probe has to be able to fail. If the alias never reached the grep line,
# every check below would pass on the real grep and say nothing about the
# shipped file.
for shell in bash zsh fish; do
  command -v "$shell" >/dev/null 2>&1 || continue
  printf 'alias grep=%s\n' "'printf \"ALIAS REACHED\\n\" #'" >"$TMP/canary.$shell"
  check "$shell: an alias in a sourced file reaches a later line, so this probe works" \
    "$(run_in_shell "$shell" 'grep whatever' "$TMP/canary.$shell")" "ALIAS REACHED"
done

for shell in bash zsh fish; do
  if ! command -v "$shell" >/dev/null 2>&1; then
    fail "$shell is not installed, so its aliases cannot be checked"
    continue
  fi
  out=$(grep_through "$shell"); rc=$?
  check "$shell: grep -r still recurses and finds the file" \
    "$out" "./sub/a.txt:hello world"
  check "$shell: and returns rather than recursing into itself" "$rc" "0"
done

# The static half, so the reason stays visible even where a shell is missing.
# grep carries no alias at all now, not a corrected one: an alias that only
# adds a colour flag still puts a name between the user and the tool, and the
# next person to edit that line is the one this check is for.
aliased=0
while read -r n; do aliased=$((aliased + n)); done < <(
  grep -cE "^[[:space:]]*alias grep=" \
    "$BIN/bashrc.sh" "$BIN/zsh.sh" "$BIN/fish.fish" | cut -d: -f2
)
check "no shell aliases grep to anything, rg included" "$aliased" "0"

# Both remain installed. Neither is being dropped, only untangled.
check "rg is still a package hyprsimple installs" \
  "$(grep -cx 'ripgrep' "$REPO/packages.txt")" "1"
check "and grep comes from base, so it is there to be left alone" \
  "$(command -v grep >/dev/null 2>&1 && echo yes || echo no)" "yes"

# ---- a usage line has to name something that exists -----------------------
#
# search_by_keyword.sh printed "Usage sk [keyword]". There has never been an sk,
# not as a script and not as an alias in any of the three shells, so the one
# message the script prints told the user to run a command that does not exist.

bad_usage=()
while IFS= read -r line; do
  cmd="${line#*Usage: }"
  cmd="${cmd%% *}"
  # $0 and $(basename ...) name the script by definition, so there is nothing
  # to verify in them.
  case "$cmd" in "" | '$0' | '$(basename' | "Usage"*) continue ;; esac
  [[ -f "$BIN/$cmd" ]] && continue
  printf '%s\n' "$bash_names" | grep -qx "$cmd" && continue
  bad_usage+=("$cmd")
done < <(grep -hoE 'Usage:? [a-zA-Z0-9_.$/(-]+' "$BIN"/*.sh | LC_ALL=C sort -u)

bad_usage_str=""
(( ${#bad_usage[@]} > 0 )) && bad_usage_str="$(printf '%s ' "${bad_usage[@]}")"
check "every usage line names a script or an alias that exists" "$bad_usage_str" ""

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
