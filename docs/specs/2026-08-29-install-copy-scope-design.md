---
title: Installers copy only tracked content
date: 2026-08-29
status: draft
---

# Installers copy only tracked content: Design

## Problem

`install.sh:386` and `bootstrap.sh:84` both populate the canonical install with a bare recursive copy of their source directory:

```bash
cp -a "$DOTFILES_DIR" "$HYPRSIMPLE_PATH"
```

`cp -a` does not consult git, so it takes everything present, including paths `.gitignore` excludes.

This is not hypothetical. The maintainer's install at `~/.local/share/hyprsimple` contained `external/omarchy`, a 206 MB vendored clone that is gitignored, tracked by nothing, and read by no script. It arrived because `install.sh` ran in a working directory that happened to contain it. Measured before removal:

| | |
|---|---|
| install total | 427 MB |
| `.git` | 194 MB |
| `external/omarchy` | 206 MB |
| `.config` theme copies | 27 MB |
| everything else | 1.5 MB |

The tracked tree is 28 MB. Everything above `.git` was waste.

`bootstrap.sh` escapes the bug only when it clones fresh at line 68. Line 61 deliberately uses a local checkout when one is present, and that path has the same defect.

`hyprsimple-update` does not have this bug. It transfers changes with `git pull --ff-only` and never copies a tree.

## Goals

1. A canonical install created by either script contains no path that `.gitignore` excludes. Verified by building an install from a fixture source holding an ignored directory, an ignored nested git repository, and an ignored top-level directory, then asserting none of the three is present.
2. The install still works: `.git` present with `origin` intact, file modes preserved, symlinks preserved. Verified by comparing against `git ls-files` and by checking the mode of one known-executable and one known-0644 file.
3. `git -C <install> status --porcelain` produces no output immediately after installation, so `hyprsimple-update:32` will not refuse to pull.
4. A source directory that is not a git repository still installs, via the existing copy behaviour.
5. Installing from a checkout with uncommitted changes prints a warning naming that the changes are not installed.

## Non-goals

- **`hyprsimple-update` is not changed.** It has no equivalent defect.
- **The 194 MB `.git` is not addressed.** Every install carries the repository's full history, which is a larger win than this one, but a shallow install cannot `pull --ff-only` normally, so it requires changing `hyprsimple-update` as well. Separate work.
- **Files ignored inside `.config/` and `.local/` are out of scope only in the sense that no extra mechanism is added for them.** `git archive` excludes them automatically, which is a free improvement rather than a designed one.
- **The copy from the repo into `~/.config` is untouched.** `install.sh:417`, `:437` and `:452` keep their current behaviour, including the destructive `backup_if_exists`.
- **No CI drift check.** An earlier draft of this design used a hand-maintained whitelist and needed one. `git archive` removes the list, so there is nothing to drift.

## Constraints

- `hyprsimple-update.sh:29` requires `.git` inside the install, and `:39` runs `git pull --ff-only`. Any approach that drops the git directory breaks updating, which rules out `git archive` alone.
- `hyprsimple-update.sh:32` refuses to pull when the install has local changes. An install whose working tree does not match `HEAD` can therefore never update itself. This is what disqualified the whitelist approach: keeping `.git` while shipping a subset of tracked files leaves 15 tracked paths showing as deleted.
- `install.sh` runs under `set -eEo pipefail`. A failing command in the copy path aborts the installer.
- `bootstrap.sh` must remain standalone so it can be curled and piped, so it cannot source a helper from the repo.
- `bootstrap.sh:88` runs `fetch --unshallow` after the copy. A `.git` copied from a shallow clone is still shallow, so that step stays necessary.
- The repository contains 8 symlinks and files at mode 0755 and 0644. Both must survive the copy.

## Approach

**Chosen: `git archive HEAD` for the tree, plus a separate copy of `.git`, with a fallback to the current `cp -a` when the source is not a repository.**

```bash
if git -C "$SOURCE" rev-parse --git-dir &>/dev/null; then
  mkdir -p "$HYPRSIMPLE_PATH"
  git -C "$SOURCE" archive HEAD | tar -x -C "$HYPRSIMPLE_PATH"
  cp -a "$SOURCE/.git" "$HYPRSIMPLE_PATH/.git"
else
  cp -a "$SOURCE" "$HYPRSIMPLE_PATH"
fi
```

`git archive` is an exact, self-maintaining list of tracked content. Measured against this repository it reproduces all 246 tracked entries with no difference in either direction, preserves the executable bit and all 8 symlinks, and yields 28 MB instead of 427 MB.

Copying `.git` separately keeps `origin`, the branch and the reflog, which is what `hyprsimple-update` needs.

Because the extracted tree is exactly `HEAD` and `.git` says `HEAD`, the resulting install is clean. That satisfies Goal 3 and incidentally fixes a second latent problem: under the previous behaviour, installing from a checkout with uncommitted edits produced an install `hyprsimple-update` would refuse to pull, discovered only later.

The one behaviour change is that uncommitted edits to tracked files are no longer installed. Goal 5 makes that visible rather than silent.

Both scripts get the same block. `bootstrap.sh` cannot source it from the repo, so this is a deliberate two-copy duplication of about eight lines.

## Alternatives considered

**Explicit whitelist array in both scripts.** The maintainer initially preferred listing directories rather than invoking git. Investigation showed the list cannot be the eight paths the runtime reads: keeping `.git` means git compares the install against `HEAD`, and every tracked file left out appears as deleted. An install built from the eight-entry minimum showed 15 dirty paths and could never update. The whitelist therefore has to equal the full tracked set, at which point it is a hand-maintained duplicate of `git ls-files` requiring a CI check to stay honest. Rejected as strictly more work for the same result. The maintainer agreed.

**`cp -a` followed by `git clean -xdff` in the destination.** One extra line, and it preserves uncommitted edits. Rejected for three reasons: it copies 427 MB in order to delete 206 MB, it needs `-ff` rather than `-f` because a single `-f` skips nested git repositories, which is exactly how a vendored clone survives an ordinary clean, and it leaves the install dirty and therefore unupdatable whenever the source is dirty. All three were measured.

**`git ls-files` piped to `tar`.** Preserves uncommitted edits and excludes ignored paths. Rejected because it still leaves the install dirty, and because its `tar` invocation is order-sensitive in a way that is easy to get wrong.

## Testing

A fixture repository is built containing: a tracked file, an ignored top-level directory, an ignored nested git repository inside it, a second ignored top-level directory, an `origin` remote, and an uncommitted edit to the tracked file.

1. After the copy, none of the ignored paths is present.
2. The nested git repository is absent.
3. `.git` is present and `git -C <dest> remote get-url origin` matches the source.
4. `git -C <dest> status --porcelain` produces no output.
5. `bin/hyprsimple-dev-optimize-images` is mode 0755 and `migrations/1787930450.sh` is mode 0644 in a real extraction of this repository.
6. The count of regular files plus symlinks in a real extraction equals `git ls-files | wc -l`, and the set difference is empty in both directions.
7. A fixture whose source directory is not a git repository still produces a populated install.
8. Installing from a dirty source prints the Goal 5 warning, and installing from a clean source does not.

## Open questions

N/A: the one open decision, whitelist versus `git archive`, was resolved before this spec was written and is recorded under Alternatives.
