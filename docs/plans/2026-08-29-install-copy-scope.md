# Installers copy only tracked content: Implementation Plan

**Spec:** docs/specs/2026-08-29-install-copy-scope-design.md
**Goal:** Stop `install.sh` and `bootstrap.sh` copying gitignored paths into the canonical install, so an install contains the tracked tree plus `.git` and nothing else.
**Architecture:** Each script's copy becomes `git archive HEAD` piped to `tar`, plus a separate `cp -a` of `.git`, falling back to today's `cp -a` when the source is not a repository. Both scripts carry their own copy of the block, because `bootstrap.sh` must stay standalone for curl-and-pipe. A new committed test exercises the real functions against fixtures.

## Global constraints

- `hyprsimple-update.sh:29` requires `.git` inside the install and `:39` runs `git pull --ff-only`, so the git directory must survive the copy.
- `hyprsimple-update.sh:32` refuses to pull when the install has local changes, so the install's working tree must match `HEAD` immediately after installation.
- `install.sh` runs under `set -eEo pipefail`. A failing command in the copy path aborts the installer.
- `bootstrap.sh` must remain standalone and curl-able. It cannot source a helper from the repo, so the block is deliberately duplicated.
- `bootstrap.sh:88` runs `fetch --unshallow` after the copy and must keep doing so, because a `.git` copied from a shallow clone is still shallow.
- The copy from the repo into `~/.config` is untouched. `install.sh:417`, `:437` and `:452` keep their current behaviour.
- `hyprsimple-update` is out of scope. It has no equivalent defect.
- Commit messages carry no `Co-Authored-By` trailer.
- No em dashes and no semicolons in prose, including code comments and commit messages.

## Notes for the implementer

`install.sh:5` names the source `DOTFILES_DIR`. `bootstrap.sh:62` and `:65` name it `SOURCE_DIR`. The blocks are otherwise identical, so keep each script's own variable name rather than renaming either.

`install_to_canonical_path()` at `install.sh:371` currently references only `$DOTFILES_DIR`, `$HYPRSIMPLE_PATH`, `${RED}`, `${GREEN}` and `${NC}`, which is what makes it extractable and testable in isolation. Task 1 adds one more, `${YELLOW}`, defined at `install.sh:20`, and the test defines it alongside the others. Keep the set that small: the test loads the function with `eval`, so any global it references must be declared in the test too.

---

### Task 1: Copy only tracked content in install.sh → verify: `bash test/install-copy-test.sh` exits 0

**Files:**
- Modify: `install.sh:371-388`
- Create: `test/install-copy-test.sh`

There is no `test/` directory in this repository yet. This task creates it.

- [ ] Step 1: Replace the body of `install_to_canonical_path()` at `install.sh:371-388`. Replace:

```bash
install_to_canonical_path() {
  if [[ $DOTFILES_DIR = "$HYPRSIMPLE_PATH" ]]; then
    return 0
  fi

  if [[ -e $HYPRSIMPLE_PATH ]]; then
    if [[ ! -f "$HYPRSIMPLE_PATH/install.sh" ]]; then
      echo -e "${RED}$HYPRSIMPLE_PATH exists but does not look like a hyprsimple checkout.${NC}"
      echo -e "${RED}Move it aside and re-run this installer.${NC}"
      return 1
    fi
    rm -rf "$HYPRSIMPLE_PATH"
  fi

  mkdir -p "$(dirname "$HYPRSIMPLE_PATH")"
  cp -a "$DOTFILES_DIR" "$HYPRSIMPLE_PATH"
  echo -e "${GREEN}hyprsimple installed to $HYPRSIMPLE_PATH${NC}"
}
```

with:

```bash
install_to_canonical_path() {
  if [[ $DOTFILES_DIR = "$HYPRSIMPLE_PATH" ]]; then
    return 0
  fi

  if [[ -e $HYPRSIMPLE_PATH ]]; then
    if [[ ! -f "$HYPRSIMPLE_PATH/install.sh" ]]; then
      echo -e "${RED}$HYPRSIMPLE_PATH exists but does not look like a hyprsimple checkout.${NC}"
      echo -e "${RED}Move it aside and re-run this installer.${NC}"
      return 1
    fi
    rm -rf "$HYPRSIMPLE_PATH"
  fi

  mkdir -p "$HYPRSIMPLE_PATH"

  # Copy only what git tracks. A bare `cp -a` of the source directory also
  # takes whatever .gitignore excludes: vendored checkouts, build output,
  # scratch files. git archive is an exact, self-maintaining list of tracked
  # content and preserves file modes and symlinks. .git is copied separately
  # because hyprsimple-update needs it to pull.
  if git -C "$DOTFILES_DIR" rev-parse --git-dir &>/dev/null; then
    if [[ -n $(git -C "$DOTFILES_DIR" status --porcelain) ]]; then
      echo -e "${YELLOW}Uncommitted changes in $DOTFILES_DIR will not be installed. Installing HEAD.${NC}"
    fi
    git -C "$DOTFILES_DIR" archive HEAD | tar -x -C "$HYPRSIMPLE_PATH"
    cp -a "$DOTFILES_DIR/.git" "$HYPRSIMPLE_PATH/.git"
  else
    # No index to consult, for example a downloaded tarball. Copy everything.
    cp -a "$DOTFILES_DIR/." "$HYPRSIMPLE_PATH/"
  fi

  echo -e "${GREEN}hyprsimple installed to $HYPRSIMPLE_PATH${NC}"
}
```

Note two changes beyond the copy itself. `mkdir -p` now creates `$HYPRSIMPLE_PATH` rather than its parent, because `tar -x -C` needs the directory to exist. The fallback copies `"$DOTFILES_DIR/."` into an existing directory rather than `"$DOTFILES_DIR"` onto a missing one, which is what preserves the old result now that the directory is pre-created.

The function now also references `${YELLOW}`. That global is defined at `install.sh:20`, and the test in Step 2 must define it too.

- [ ] Step 2: Create `test/install-copy-test.sh` with this content:

```bash
#!/bin/bash
# Checks that the installer copies tracked content only.
#
# Extracts install_to_canonical_path from install.sh and runs it against
# fixtures, so the test exercises the real function rather than a copy of it.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

failures=0

pass() { printf 'ok - %s\n' "$1"; }
fail() { printf 'not ok - %s\n' "$1" >&2; failures=$((failures + 1)); }
check() { if [[ $2 == "$3" ]]; then pass "$1"; else printf 'not ok - %s (want %s, got %s)\n' "$1" "$3" "$2" >&2; failures=$((failures + 1)); fi; }

# The function depends on these globals and nothing else.
RED='' GREEN='' YELLOW='' NC=''
eval "$(sed -n '/^install_to_canonical_path() {/,/^}/p' "$REPO/install.sh")"

# ---- fixture: a checkout carrying ignored paths -------------------------

build_fixture() {
  local src="$1"
  mkdir -p "$src"
  git -C "$src" init -q
  git -C "$src" config user.email test@example.com
  git -C "$src" config user.name test
  git -C "$src" remote add origin https://github.com/rizukirr/hyprsimple

  mkdir -p "$src/.config" "$src/.local/bin"
  printf 'tracked\n' >"$src/install.sh"
  printf 'tracked\n' >"$src/.config/kept.conf"
  printf '#!/bin/bash\n' >"$src/.local/bin/kept.sh"
  chmod 0755 "$src/.local/bin/kept.sh"
  ln -sf kept.conf "$src/.config/link.conf"
  printf 'ignored-dir/\nscratch/\n' >"$src/.gitignore"
  git -C "$src" add -A
  git -C "$src" commit -qm init

  # Everything below is ignored and must not reach the install.
  mkdir -p "$src/ignored-dir" "$src/scratch"
  printf 'junk\n' >"$src/ignored-dir/junk.txt"
  printf 'junk\n' >"$src/scratch/notes.md"
  git -C "$src/ignored-dir" init -q vendored
  git -C "$src/ignored-dir/vendored" config user.email test@example.com
  git -C "$src/ignored-dir/vendored" config user.name test
  printf 'x\n' >"$src/ignored-dir/vendored/file"
  git -C "$src/ignored-dir/vendored" add -A
  git -C "$src/ignored-dir/vendored" commit -qm x
}

DOTFILES_DIR="$TMP/src"
HYPRSIMPLE_PATH="$TMP/install"
build_fixture "$DOTFILES_DIR"
install_to_canonical_path >/dev/null

check "ignored directory is not installed"    "$([[ -e $HYPRSIMPLE_PATH/ignored-dir ]] && echo present || echo absent)" absent
check "nested git repo is not installed"      "$([[ -e $HYPRSIMPLE_PATH/ignored-dir/vendored ]] && echo present || echo absent)" absent
check "second ignored directory is absent"    "$([[ -e $HYPRSIMPLE_PATH/scratch ]] && echo present || echo absent)" absent
check "tracked config is installed"           "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes
check "git directory survives"                "$([[ -d $HYPRSIMPLE_PATH/.git ]] && echo yes || echo no)" yes
check "origin survives"                       "$(git -C "$HYPRSIMPLE_PATH" remote get-url origin)" https://github.com/rizukirr/hyprsimple
check "executable bit survives"               "$(stat -c%a "$HYPRSIMPLE_PATH/.local/bin/kept.sh")" 755
check "symlink survives as a symlink"         "$([[ -L $HYPRSIMPLE_PATH/.config/link.conf ]] && echo yes || echo no)" yes
check "install tree is clean, so it can pull" "$(git -C "$HYPRSIMPLE_PATH" status --porcelain)" ""

# ---- uncommitted changes are reported and not installed ------------------

DOTFILES_DIR="$TMP/dirty"
HYPRSIMPLE_PATH="$TMP/dirty-install"
build_fixture "$DOTFILES_DIR"
printf 'uncommitted\n' >>"$DOTFILES_DIR/.config/kept.conf"
output="$(install_to_canonical_path)"

if grep -q "will not be installed" <<<"$output"; then
  pass "dirty source is reported"
else
  fail "dirty source is reported"
fi
check "dirty source installs HEAD, not the edit" "$(cat "$HYPRSIMPLE_PATH/.config/kept.conf")" tracked
check "install from a dirty source is still clean" "$(git -C "$HYPRSIMPLE_PATH" status --porcelain)" ""

# ---- a source that is not a git repository still installs ----------------

DOTFILES_DIR="$TMP/plain"
HYPRSIMPLE_PATH="$TMP/plain-install"
mkdir -p "$DOTFILES_DIR/.config"
printf 'tracked\n' >"$DOTFILES_DIR/install.sh"
printf 'tracked\n' >"$DOTFILES_DIR/.config/kept.conf"
install_to_canonical_path >/dev/null
check "non-repo source still installs" "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes

# ---- a clean source produces no warning ----------------------------------

DOTFILES_DIR="$TMP/clean"
HYPRSIMPLE_PATH="$TMP/clean-install"
build_fixture "$DOTFILES_DIR"
output="$(install_to_canonical_path)"
if grep -q "will not be installed" <<<"$output"; then
  fail "clean source produces no warning"
else
  pass "clean source produces no warning"
fi

if ((failures > 0)); then
  printf '\n%s check(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nall checks passed\n'
```

- [ ] Step 3: `chmod +x test/install-copy-test.sh`
- [ ] Step 4: Run `bash -n install.sh` and require exit 0.
- [ ] Step 5: Run `bash -n test/install-copy-test.sh` and require exit 0.
- [ ] Step 6: Run `bash test/install-copy-test.sh` and require exit 0.
- [ ] Step 7: Confirm the fix against this repository rather than only a fixture. Extract the tracked tree with `git archive HEAD | tar -x -C "$(mktemp -d)"` into a directory you name, then compare its regular files plus symlinks against `git ls-files` and require the set difference to be empty in both directions.
- [ ] Step 8: Commit.

---

### Task 2: Copy only tracked content in bootstrap.sh → verify: `bash test/install-copy-test.sh` exits 0, and `grep -q copy_source_to_canonical_path test/install-copy-test.sh` exits 0

**Files:**
- Modify: `bootstrap.sh:82-91`
- Modify: `test/install-copy-test.sh`

`bootstrap.sh` performs its copy inline rather than in a function, which makes it untestable in isolation. This task wraps it in a function so the test can exercise the real code, matching what `install.sh` already does.

- [ ] Step 1: Replace `bootstrap.sh:82-91`. Replace:

```bash
echo -e "\n${YELLOW}Installing hyprsimple to $HYPRSIMPLE_PATH...${NC}"
mkdir -p "$(dirname "$HYPRSIMPLE_PATH")"
cp -a "$SOURCE_DIR" "$HYPRSIMPLE_PATH"

# A shallow clone can't be pulled from later, so give it real history
if [[ -d "$HYPRSIMPLE_PATH/.git" ]]; then
  git -C "$HYPRSIMPLE_PATH" fetch --unshallow origin "$REPO_REF" >/dev/null 2>&1 || true
else
  echo -e "${YELLOW}Source was not a git checkout — hyprsimple-update will not be able to pull.${NC}"
fi
```

with:

```bash
copy_source_to_canonical_path() {
  mkdir -p "$HYPRSIMPLE_PATH"

  # Copy only what git tracks. A bare `cp -a` of the source directory also
  # takes whatever .gitignore excludes: vendored checkouts, build output,
  # scratch files. git archive is an exact, self-maintaining list of tracked
  # content and preserves file modes and symlinks. .git is copied separately
  # because hyprsimple-update needs it to pull.
  if git -C "$SOURCE_DIR" rev-parse --git-dir &>/dev/null; then
    if [[ -n $(git -C "$SOURCE_DIR" status --porcelain) ]]; then
      echo -e "${YELLOW}Uncommitted changes in $SOURCE_DIR will not be installed. Installing HEAD.${NC}"
    fi
    git -C "$SOURCE_DIR" archive HEAD | tar -x -C "$HYPRSIMPLE_PATH"
    cp -a "$SOURCE_DIR/.git" "$HYPRSIMPLE_PATH/.git"
  else
    # No index to consult, for example a downloaded tarball. Copy everything.
    cp -a "$SOURCE_DIR/." "$HYPRSIMPLE_PATH/"
  fi
}

echo -e "\n${YELLOW}Installing hyprsimple to $HYPRSIMPLE_PATH...${NC}"
copy_source_to_canonical_path

# A shallow clone can't be pulled from later, so give it real history
if [[ -d "$HYPRSIMPLE_PATH/.git" ]]; then
  git -C "$HYPRSIMPLE_PATH" fetch --unshallow origin "$REPO_REF" >/dev/null 2>&1 || true
else
  echo -e "${YELLOW}Source was not a git checkout, so hyprsimple-update will not be able to pull.${NC}"
fi
```

The final message loses its em dash, because the project's writing rules disallow one and this line is being rewritten anyway.

- [ ] Step 2: Extend `test/install-copy-test.sh`. After the existing `eval` that loads `install_to_canonical_path`, add a second `eval` that loads the bootstrap function:

```bash
eval "$(sed -n '/^copy_source_to_canonical_path() {/,/^}/p' "$REPO/bootstrap.sh")"
```

Then append this section immediately before the final `if ((failures > 0)); then` block:

```bash
# ---- bootstrap.sh does the same thing ------------------------------------

SOURCE_DIR="$TMP/bsrc"
HYPRSIMPLE_PATH="$TMP/bsrc-install"
build_fixture "$SOURCE_DIR"
copy_source_to_canonical_path >/dev/null

check "bootstrap: ignored directory is not installed" "$([[ -e $HYPRSIMPLE_PATH/ignored-dir ]] && echo present || echo absent)" absent
check "bootstrap: nested git repo is not installed"   "$([[ -e $HYPRSIMPLE_PATH/ignored-dir/vendored ]] && echo present || echo absent)" absent
check "bootstrap: tracked config is installed"        "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes
check "bootstrap: git directory survives"             "$([[ -d $HYPRSIMPLE_PATH/.git ]] && echo yes || echo no)" yes
check "bootstrap: install tree is clean"              "$(git -C "$HYPRSIMPLE_PATH" status --porcelain)" ""

SOURCE_DIR="$TMP/bplain"
HYPRSIMPLE_PATH="$TMP/bplain-install"
mkdir -p "$SOURCE_DIR/.config"
printf 'tracked\n' >"$SOURCE_DIR/.config/kept.conf"
copy_source_to_canonical_path >/dev/null
check "bootstrap: non-repo source still installs" "$([[ -f $HYPRSIMPLE_PATH/.config/kept.conf ]] && echo yes || echo no)" yes
```

- [ ] Step 3: Run `bash -n bootstrap.sh` and require exit 0.
- [ ] Step 4: Run `bash test/install-copy-test.sh` and require exit 0.
- [ ] Step 5: Confirm no `cp -a` of a whole source directory remains in either script. Run `grep -n 'cp -a "\$DOTFILES_DIR"$\|cp -a "\$SOURCE_DIR"$' install.sh bootstrap.sh` and require a non-zero exit.
- [ ] Step 6: Commit.

---

## Final verification, after both tasks

- [ ] `bash test/install-copy-test.sh` exits 0 (spec Goals 1, 2, 3, 4 and 5).
- [ ] `bash -n install.sh` and `bash -n bootstrap.sh` both exit 0.
- [ ] `git status --porcelain` is empty.
- [ ] `grep -rn "hyprsimple-update" install.sh bootstrap.sh` shows no new call, confirming the spec's non-goal that `hyprsimple-update` is unchanged, and `git diff --name-only` against the base does not list `.local/bin/hyprsimple-update.sh`.
