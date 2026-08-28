# Repo slimming and image policy: Implementation Plan

**Spec:** docs/specs/2026-08-28-repo-slimming-design.md
**Goal:** Cut the working tree from 152 MB to under 30 MB and add a guard that keeps it there, without rewriting git history.
**Architecture:** One script owns the image policy and is the only place the limits are written down. CI runs it in check mode, contributors run it in fix mode, and Task 5 runs it once to perform the bulk conversion. Everything else in this plan is deletion, plus the few references that deletion and format conversion force.

## Global constraints

- Long edge at most 2560px, JPEG quality 82, metadata stripped.
- `.local/share/assets/wlogout/` is excluded from the optimizer: those are UI icons with alpha referenced by `.config/wlogout/style.css`.
- Never replace an image with a larger one. Keep the original when the converted file is not smaller.
- Do not introduce symlinks under any `backgrounds/` directory. `theme-switcher.sh:109`, `wallpaper-switcher.sh:24` and `.config/rofi/scripts/wallpaper-selector.sh:30` all select with `find -type f`, which does not match symlinks.
- When deleting one member of a duplicate pair inside a theme, delete the higher-numbered file. `theme-switcher.sh:109` takes `sort | head -1` as the theme default.
- Do not change the cache filename `~/.cache/current_lockscreen.png`. `.config/hypr/hyprlock.conf:13` points at it.
- Do not rewrite git history. No force push, no `filter-repo`.
- Migrations are executed with `bash`, not sourced, and stay mode `0644` (`migrations/README.md:14`). Use `$HYPRSIMPLE_PATH` to reach the repo. Every migration is idempotent (`migrations/README.md:17`).
- Commit messages carry no `Co-Authored-By` trailer.
- ImageMagick is a contributor and CI dependency, not a runtime one. The development machine has ImageMagick 7 (observed: 7.1.2-30), which provides `magick`. GitHub's Ubuntu runners install ImageMagick 6, which provides `convert` and `identify` instead. The optimizer supports both.

## Deviation from the spec, for review

The spec's Approach section specifies one pull request with three commits. This plan has seven tasks and therefore seven commits, still in one pull request. The spec's stated reason for splitting was that a single commit mixing a 127 MB deletion with a rewrite of every image cannot be reviewed by eye, and seven serves that reason better than three: it separates the tool from its output, and the CI guard and the migration from both. Flagging rather than silently changing it. Say if you want it collapsed back to three.

---

### Task 1: Delete unreferenced files → verify: `grep -rn "themes/.*rofi" .local/bin .config` exits non-zero, and `git status --porcelain` produces no output

**Files:**
- Delete: `.config/hypr/themes/*/rofi/` (167 files)
- Delete: `.local/share/wallpapers/` (3 files)
- Delete: `.config/hypr/themes/catppuccin/wallpaper.jpg`
- Delete: `.config/hypr/themes/rosepine/wallpaper.jpg`

- [x] Step 1: Record the starting size. Run `du -sh --exclude=.git --exclude=external .` and keep the value for the commit message.
- [x] Step 2: Confirm nothing reads the rofi trees. Run `grep -rn "themes/.*rofi" .local/bin .config` and require a non-zero exit.
- [x] Step 3: Confirm nothing reads the shared wallpapers. Run `grep -rn "share/wallpapers" .local .config install.sh bootstrap.sh migrations` and require a non-zero exit. The search is scoped to code on purpose: `docs/` holds the spec and plan for this deletion, and both name the path by design, so a repo-wide search can never pass.
- [x] Step 4: Confirm every theme has a `backgrounds/` directory, which is what makes the `wallpaper.jpg` fallback at `theme-switcher.sh:110` unreachable. Run:
      `for t in .config/hypr/themes/*/; do n=$(basename "$t"); [[ $n == templates ]] && continue; [[ -d "$t/backgrounds" ]] || echo "MISSING $n"; done`
      and require no output.
- [x] Step 5: `git rm -r --quiet .config/hypr/themes/*/rofi .local/share/wallpapers .config/hypr/themes/catppuccin/wallpaper.jpg .config/hypr/themes/rosepine/wallpaper.jpg`
- [x] Step 6: Record the ending size with the same command as Step 1.
- [x] Step 7: Commit, with both sizes from Steps 1 and 6 in the message.

---

### Task 2: Untrack generated theme output → verify: `git ls-files | grep -q "generated/"` exits non-zero, and `.config/hypr/themes/catppuccin/generated/hyprland-colors.lua` still exists on disk

**Files:**
- Modify: git index only. No file content changes.

`.gitignore:35` already ignores `.config/hypr/themes/*/generated/`. The rule has no effect because the files were tracked before it was added, and gitignore does not apply to tracked files.

- [x] Step 1: Observe which are tracked. Run `git ls-files | grep "generated/"`.
- [x] Step 2: `git rm --cached --quiet .config/hypr/themes/*/generated/*`
- [x] Step 3: Confirm the working files survived, since `theme-apply-templates.sh` regenerates them but a live machine should not need a theme switch to get them back. Run `ls .config/hypr/themes/catppuccin/generated/hyprland-colors.lua`.
- [x] Step 4: Commit.

---

### Task 3: Remove duplicate backgrounds within a theme → verify: the command in Step 3 exits 0, meaning no two files inside any single `backgrounds/` directory share an md5

Each of these is byte-identical to a lower-numbered file in the same theme, so the live wallpaper cycler shows the same photograph twice in succession. This is a display bug, not a size measure.

**Files:**
- Delete: `.config/hypr/themes/ethereal/backgrounds/1-morning-angel.jpg`
- Delete: `.config/hypr/themes/ethereal/backgrounds/2-sunset-beach.jpg`
- Delete: `.config/hypr/themes/catppuccin/backgrounds/4-home-fantasy.jpg`

- [x] Step 1: Confirm each is a duplicate of its lower-numbered partner before deleting. Run:
      `md5sum .config/hypr/themes/ethereal/backgrounds/0-morning-angel.jpg .config/hypr/themes/ethereal/backgrounds/1-morning-angel.jpg .config/hypr/themes/ethereal/backgrounds/1-sunset-beach.jpg .config/hypr/themes/ethereal/backgrounds/2-sunset-beach.jpg .config/hypr/themes/catppuccin/backgrounds/0-home-fantasy.jpg .config/hypr/themes/catppuccin/backgrounds/4-home-fantasy.jpg`
      and require the pairs to match.
- [x] Step 2: `git rm --quiet .config/hypr/themes/ethereal/backgrounds/1-morning-angel.jpg .config/hypr/themes/ethereal/backgrounds/2-sunset-beach.jpg .config/hypr/themes/catppuccin/backgrounds/4-home-fantasy.jpg`
- [x] Step 3: Confirm no intra-theme duplicates remain. Run:
      `! (for d in .config/hypr/themes/*/backgrounds; do md5sum "$d"/* 2>/dev/null | awk '{print $1}' | sort | uniq -d; done | grep -q .)`
      and require exit 0. The leading `!` makes the clean case the zero exit, so the clause works as a gate. Without it the loop's status comes from the final `grep -q`, which is 1 when nothing is wrong.
- [x] Step 4: Confirm both themes still number contiguously from 0, so the theme default is unchanged. Run `ls .config/hypr/themes/ethereal/backgrounds .config/hypr/themes/catppuccin/backgrounds`.
- [x] Step 5: Commit.

---

### Task 4: Add the image optimizer → verify: `bash -n bin/hyprsimple-dev-optimize-images` exits 0, and `bin/hyprsimple-dev-optimize-images --check` exits non-zero while the tree is still unoptimized AND lists at least 10 offending files, which a script that aborts on its first finding cannot do

The repo has no top-level `bin/` today. This directory is created here, and holds contributor tooling that `install.sh` must not copy into a user's home.

**Files:**
- Create: `bin/hyprsimple-dev-optimize-images`

- [x] Step 1: Create the directory and the file with this content:

```bash
#!/bin/bash
# Enforce the repo image policy: long edge <= MAX_EDGE, JPEG at QUALITY, no metadata.
#
#   hyprsimple-dev-optimize-images           rewrite offending images in place
#   hyprsimple-dev-optimize-images --check   report offenders, write nothing, exit 1 if any
#
# CI runs --check. Contributors run the bare form to fix what it reports.

set -euo pipefail

MAX_EDGE=2560
QUALITY=82

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO"

check_only=false
case "${1:-}" in
  --check) check_only=true ;;
  "") ;;
  *)
    echo "Usage: $(basename "$0") [--check]" >&2
    exit 2
    ;;
esac

# ImageMagick 7 exposes `magick`. ImageMagick 6, which is what Ubuntu still
# ships and therefore what GitHub's runners install, exposes `convert` and
# `identify` instead. Support both rather than pinning CI to one of them.
if command -v magick &>/dev/null; then
  im_identify() { magick identify "$@"; }
  im_convert() { magick "$@"; }
elif command -v identify &>/dev/null && command -v convert &>/dev/null; then
  im_identify() { identify "$@"; }
  im_convert() { convert "$@"; }
else
  echo "ImageMagick is required: pacman -S imagemagick" >&2
  exit 2
fi

# Paths the policy covers. .local/share/assets/wlogout is deliberately absent:
# those are UI icons with alpha, referenced by .config/wlogout/style.css.
mapfile -t targets < <(
  find .config/hypr/themes/*/backgrounds .config/hypr/themes/*/lockscreen.* assets \
    -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \) \
    2>/dev/null | sort
)

# Counters are incremented by assignment, not ((n++)). Post-increment returns
# the OLD value, so the first ((n++)) on a zero counter has a false exit status
# and `set -e` kills the script after one iteration.
violations=0
converted=0

for f in "${targets[@]}"; do
  # The trailing \n matters: `identify -format` emits no delimiter of its own, and
  # bash `read` returns 1 on a stream that ends without one even after populating
  # its variables. Without it, `|| continue` fires on every file and the script
  # silently becomes a no-op in both modes.
  read -r w h < <(im_identify -format '%w %h\n' "$f[0]" 2>/dev/null) || continue

  long=$w
  ((h > w)) && long=$h

  # A file is compliant only if it is already a .jpg within the size limit.
  if [[ $f == *.jpg ]] && ((long <= MAX_EDGE)); then
    continue
  fi

  if $check_only; then
    printf '%s (%sx%s)\n' "$f" "$w" "$h"
    violations=$((violations + 1))
    continue
  fi

  out="${f%.*}.jpg"
  tmp="$(mktemp --suffix=.jpg)"
  im_convert "$f[0]" -resize "${MAX_EDGE}x${MAX_EDGE}>" -quality "$QUALITY" -strip "$tmp"

  # Never trade a small file for a bigger one. Same-name case included: if the
  # rewrite of an existing .jpg gains bytes, keep what is already committed.
  if [[ $out == "$f" ]] && (($(stat -c%s "$tmp") >= $(stat -c%s "$f"))); then
    rm -f "$tmp"
    continue
  fi

  mv -f "$tmp" "$out"
  chmod 0644 "$out"
  [[ $out != "$f" ]] && rm -f "$f"
  printf 'optimized %s -> %s\n' "$f" "$out"
  converted=$((converted + 1))
done

if $check_only; then
  if ((violations > 0)); then
    echo "$violations image(s) violate the policy. Run bin/$(basename "$0") to fix." >&2
    exit 1
  fi
  echo "All images comply."
fi

exit 0
```

- [x] Step 2: `chmod +x bin/hyprsimple-dev-optimize-images`
- [x] Step 3: Run `bash -n bin/hyprsimple-dev-optimize-images` and require exit 0.
- [x] Step 4: Run `bin/hyprsimple-dev-optimize-images --check` and require a non-zero exit, because the tree has not been converted yet. This is the negative case for the guard.
- [x] Step 5: Confirm `install.sh` copies only `.local/bin` and `.local/share`, so the new `bin/` reaches no user. Run `grep -n "DOTFILES_DIR/.local" install.sh`.
- [x] Step 6: Commit.

---

### Task 5: Convert every image and fix the references the conversion forces → verify: `bin/hyprsimple-dev-optimize-images --check` exits 0, a second consecutive run of the bare command leaves `git status --porcelain` with no output, and `du -sh --exclude=.git --exclude=external .` reports under 30 MB, which a script that converted nothing cannot satisfy

Two references break when file extensions change, and both are fixed here rather than in a later task, because between the conversion and the fix the theme switcher is broken.

**Files:**
- Modify: every image under `.config/hypr/themes/*/backgrounds/`, `.config/hypr/themes/*/lockscreen.*`, `assets/`
- Modify: `.local/bin/theme-switcher.sh:137-143`
- Modify: `README.md:8`, `README.md:12`, `README.md:16`

- [ ] Step 1: Record the starting size. Run `du -sh --exclude=.git --exclude=external .`.
- [ ] Step 2: Run `bin/hyprsimple-dev-optimize-images`.
- [ ] Step 3: Replace the lockscreen block at `.local/bin/theme-switcher.sh:137-143`. The lookup is hardcoded to `lockscreen.png` and the file is now `lockscreen.jpg`. The cache filename stays `current_lockscreen.png` because `.config/hypr/hyprlock.conf:13` points at it, and hyprlock reads content rather than extension. Replace:

```bash
# Lockscreen
rm -f "$CACHE_DIR/current_lockscreen.png"
if [[ -f "$THEME_PATH/lockscreen.png" ]]; then
  cp "$THEME_PATH/lockscreen.png" "$CACHE_DIR/current_lockscreen.png"
elif [[ -n "$WALLPAPER" ]]; then
  cp "$WALLPAPER" "$CACHE_DIR/current_lockscreen.png"
fi
```

with:

```bash
# Lockscreen. The cache filename keeps its .png suffix because hyprlock.conf
# points at it by name. Hyprlock sniffs content, so a JPEG behind that name is
# fine, and the fallback below has always written one.
rm -f "$CACHE_DIR/current_lockscreen.png"
THEME_LOCKSCREEN=$(find "$THEME_PATH" -maxdepth 1 -type f -name 'lockscreen.*' | sort | head -1)
if [[ -n "$THEME_LOCKSCREEN" ]]; then
  cp "$THEME_LOCKSCREEN" "$CACHE_DIR/current_lockscreen.png"
elif [[ -n "$WALLPAPER" ]]; then
  cp "$WALLPAPER" "$CACHE_DIR/current_lockscreen.png"
fi
```

- [ ] Step 4: Update the three `README.md` image links from `.png` to `.jpg`. Run:
      `sed -i -E 's#\(assets/(image[0-9]+)\.png\)#(assets/\1.jpg)#g' README.md`
      The trailing `g` matters: `README.md:12` and `README.md:16` are table rows holding two image refs each, and without it one pass rewrites only the first on those lines.
- [ ] Step 5: Confirm no reference to a now-missing asset survives. Run `grep -n "assets/" README.md`, then for each path listed require the file to exist.
- [ ] Step 6: Run `bin/hyprsimple-dev-optimize-images --check` and require exit 0.
- [ ] Step 7: Prove idempotence. Run `bin/hyprsimple-dev-optimize-images` a second time, then `git status --porcelain`, and require no output beyond what Steps 2 to 4 already staged.
- [ ] Step 8: Record the ending size with the same command as Step 1.
- [ ] Step 9: Commit, with both sizes in the message.

---

### Task 6: Add the CI guard → verify: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/images.yml'))"` exits 0, and the workflow file's `run:` step names the same script path Task 4 created

This is the repository's first workflow. `.github/` currently holds only `FUNDING.yml`.

**Files:**
- Create: `.github/workflows/images.yml`

- [ ] Step 1: Create the file with this content:

```yaml
name: Images

on:
  pull_request:
    paths:
      - '.config/hypr/themes/**'
      - 'assets/**'
      - 'bin/hyprsimple-dev-optimize-images'
  push:
    branches: [main]

jobs:
  policy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install ImageMagick
        run: |
          sudo apt-get update
          sudo apt-get install -y imagemagick

      - name: Check image policy
        run: bin/hyprsimple-dev-optimize-images --check
```

- [ ] Step 2: Validate the YAML parses. Run `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/images.yml'))"`.
- [ ] Step 3: Confirm the script's ImageMagick detection covers what the runner installs. Ubuntu ships ImageMagick 6, which provides `convert` and `identify` but not `magick`, and Task 4's script handles both. Verify locally by running `env -i PATH=/usr/bin:/bin bash -c 'command -v convert identify magick'` to see which names exist, and read the workflow's job log on the pull request to confirm the check step ran rather than exiting on the dependency guard.
- [ ] Step 4: Commit.

---

### Task 7: Clean up existing installs and document the policy → verify: `bash -n migrations/1787930450.sh` exits 0, the file's mode is 0644, and running it against a fixture directory holding one extra file leaves that directory present

`install.sh` copies `.local/share/` into the user's home, so every existing install has a `~/.local/share/wallpapers/` that Task 1 deleted from the repo but cannot delete from a user's disk.

The migration filename is the unix timestamp of the last commit on `main` at planning time, per `migrations/README.md`. Observed: 1787930450.

**Files:**
- Create: `migrations/1787930450.sh`
- Create: `AGENTS.md`

- [ ] Step 1: Create `migrations/1787930450.sh` with this content:

```bash
echo "Remove the unused ~/.local/share/wallpapers directory"

# hyprsimple shipped three wallpapers in .local/share/wallpapers that no script
# ever read, and install.sh copies all of .local/share into the user's home, so
# every install carries ~20 MB of dead files. They are gone from the repo now.
#
# Only remove the directory if it still holds exactly what we shipped. A user who
# put their own images there keeps everything, including our three files, because
# telling them apart is not worth the risk of deleting someone's wallpaper.

DIR="$HOME/.local/share/wallpapers"
[[ -d $DIR ]] || exit 0

SHIPPED=(lockscreen.png wallpaper.png wallpaper2.jpg)

mapfile -t present < <(cd "$DIR" && find . -mindepth 1 -printf '%P\n' | sort)

expected=$(printf '%s\n' "${SHIPPED[@]}" | sort)
actual=$(printf '%s\n' "${present[@]}")

if [[ $actual == "$expected" ]]; then
  rm -rf "$DIR"
  echo "  Removed $DIR"
else
  echo "  Left $DIR alone: it holds files we did not ship"
fi
```

- [ ] Step 2: `chmod 0644 migrations/1787930450.sh`
- [ ] Step 3: Run `bash -n migrations/1787930450.sh` and require exit 0.
- [ ] Step 4: Test the protective branch. Build a fixture with the three shipped names plus one extra file, point `HOME` at its parent, run the migration, and require the directory to still exist.
- [ ] Step 5: Test the removal branch. Build a fixture with exactly the three shipped names, run the migration the same way, and require the directory to be gone.
- [ ] Step 6: Test idempotence, which `migrations/README.md:17` requires. Run the migration again against the now-removed fixture and require exit 0.
- [ ] Step 7: Create `AGENTS.md` covering two things: the script prefix taxonomy (`hw-` for hardware predicates returning exit codes, `toggle-`, `theme-`, `hyprsimple-` for management commands, `hyprsimple-dev-` for contributor tooling), and an image policy section that names `bin/hyprsimple-dev-optimize-images` as the authority rather than restating the numeric limits, so the two cannot drift apart.
- [ ] Step 8: Commit.

---

## Final verification, after all seven tasks

- [ ] `du -sh --exclude=.git --exclude=external .` is under 30 MB (spec Goal 1).
- [ ] `bin/hyprsimple-dev-optimize-images --check` exits 0 (spec Goal 2, positive case). Task 4 Step 4 covers the negative case.
- [ ] `git status --porcelain` produces no output after a second optimizer run (spec Goal 3).
- [ ] The Images workflow runs on the pull request and the job succeeds (spec Goal 4).
- [ ] On the live machine, switch to catppuccin, ethereal, rosepine and deep-sea. Wallpaper and lockscreen render in each, and `deep-sea/backgrounds/2-deep-sea.jpg` (converted from `.webp` by Task 5, and therefore visible to the `*.jpg` filter in `wallpaper-switcher.sh:24` for the first time) appears in the wallpaper picker (spec Goal 5).
- [ ] `git log --oneline` on the branch shows the deletion, the untracking, the dedup, the tool, the conversion, the workflow and the migration as separate commits.
