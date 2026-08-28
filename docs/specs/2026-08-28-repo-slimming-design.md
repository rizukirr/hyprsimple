---
title: Repo slimming and image policy
date: 2026-08-28
status: draft
---

# Repo slimming and image policy: Design

## Problem

A fresh checkout of hyprsimple is 152 MB. Almost none of that weight does any work.

Measured on commit `27e555e`:

| Item | Files | Size | Status |
|---|---|---|---|
| `.config/hypr/themes/*/rofi/` | 167 | 8.5 MB | No reader anywhere in the repo |
| `.local/share/wallpapers/` | 3 | 20 MB | No reader anywhere in the repo |
| Theme and wallpaper images | 50 | 134 MB | Over-provisioned, 85 percent recoverable. Includes the 20 MB row above |
| `assets/` README screenshots | 5 | 9.7 MB | 1920x1080 PNGs of screenshots |
| `themes/*/generated/*` | 16 | small | Tracked despite `.gitignore:33` |

The rofi tree, the 134 MB of images and `assets/` do not overlap and account for the checkout exactly: 8.5 + 134 + 9.7 = 152.2 MB.

Two specific forms of waste inside the 134 MB of images:

- **Resolution over-provisioning.** Wallpapers ship at up to 5000x3351. Resized to a 2560px long edge at JPEG quality 82 with metadata stripped, the whole set goes from 134 MB to 21 MB.
- **Exact duplicates, 53.5 MB.** One 8.3 MB photo exists at four paths. One 6.0 MB PNG exists at four paths. Three more pairs are duplicated inside a single theme's `backgrounds/` directory, which makes the live wallpaper cycler display the same photo twice in a row.

The repo has also regrown through this gap twice already. The dead rofi tree and the 16 tracked `generated/` files both accumulated unnoticed, the latter against a `.gitignore` rule that already existed. A one-time cleanup without a guard would leave the same gap open.

## Goals

1. A fresh checkout is under 30 MB, measured by `du -sh --exclude=.git --exclude=external .` (from 152 MB).
2. `bin/hyprsimple-dev-optimize-images --check` exits 0 on the cleaned tree, and exits 1 with a listed violation when given an image exceeding 2560px on the long edge.
3. Running `bin/hyprsimple-dev-optimize-images` twice in a row leaves `git status` clean after the second run.
4. A pull request that adds an oversized image fails CI. The repo has no workflows today, so this is also the first one.
5. On the maintainer's live machine, switching to catppuccin, ethereal, rosepine and deep-sea renders the correct wallpaper and lockscreen, and `deep-sea/backgrounds/2-deep-sea.webp` appears in the wallpaper picker for the first time.
6. No existing install loses user data. A user who added their own files to `~/.local/share/wallpapers/` keeps them.

## Non-goals

- **Git history is not rewritten.** The 177 MiB pack stays as it is. A `git filter-repo` and force push would break the 3 existing forks permanently and change every commit SHA. This was explicitly declined. A shallow clone still benefits from the working tree cleanup immediately.
- **Backgrounds are not moved out of the repo.** Fetching wallpapers from a release tarball on demand was considered and rejected for now (see Alternatives).
- **No other roadmap phases.** The helper scripts, the `hw-*` predicate layer, the CLI dispatcher and the `refresh-*` family are separate work.
- **No unrelated refactoring** of `theme-switcher.sh` beyond the one lookup that this change forces.

## Constraints

- **`find -type f` does not match symlinks.** Three call sites depend on this: `theme-switcher.sh:113`, `wallpaper-switcher.sh:24`, and `.config/rofi/scripts/wallpaper-selector.sh:30`. A symlink-based dedup would silently change which wallpaper each theme opens with. Duplicates must stay real files.
- **`theme-switcher.sh:113` takes `sort | head -1` as the theme default.** Deleting the lower-numbered member of a duplicate pair would change which wallpaper a theme opens with. Always delete the higher-numbered copy.
- **`hyprlock.conf:13` points at `~/.cache/current_lockscreen.png`.** That cache filename must not change. Hyprlock sniffs content rather than extension, and already receives a JPEG through the fallback at `theme-switcher.sh:142`, so a `.jpg` source is safe.
- **`.local/share/assets/wlogout/` must stay PNG.** Those are UI icons with alpha, referenced by `wlogout/style.css`. They are excluded from the optimizer.
- **`install.sh:452` copies all of `.local/share/` into the user's home.** Deleting `.local/share/wallpapers/` from the repo does not remove the 20 MB already installed on existing machines. That needs a migration.
- **`.gitignore:31` ignores `docs/`,** so committing this spec requires a `!docs/specs/` exception.
- ImageMagick (`magick`) is required to run the optimizer. It is a developer dependency, not a runtime one.

## Approach

**Chosen: one-time cleanup plus a CI guard, with the policy expressed as a single executable script.**

The pushback turn challenged whether the real goal was a smaller repo or a cleaner one. The maintainer chose the larger framing, so this design targets actual bytes rather than dead-code hygiene alone. A follow-up question on the history rewrite was answered "A and B only", which fixes the non-goal above.

One script owns the image policy. CI calls it in check mode, contributors call it in fix mode, and it performs the bulk cleanup once. `AGENTS.md` documents the rule and points at the script rather than restating limits that could drift.

### Components

**`bin/hyprsimple-dev-optimize-images`**

- Default mode rewrites offending images in place.
- `--check` writes nothing, lists violations, exits 1 if any.
- Policy: long edge at most 2560px, JPEG quality 82, metadata stripped.
- Scope: `.config/hypr/themes/*/backgrounds/`, `.config/hypr/themes/*/lockscreen.*`, `assets/`.
- Never replaces a file with a larger one. This matters for the existing `.webp` and for already-small PNGs.
- Idempotent. A second run reports zero changes, which is what makes `--check` meaningful rather than flaky.
- Fails with a clear message if `magick` is absent.

**`.github/workflows/images.yml`** runs `--check` on pull requests touching those paths.

**`AGENTS.md`** gains the script prefix taxonomy and an image policy section.

### Deletions

- `.config/hypr/themes/*/rofi/`, 167 files, 8.5 MB. Verified unreferenced: every rofi consumer reads `~/.config/rofi/`, and `theme-switcher.sh:51` reads the generated `rofi-colors.rasi`.
- `.local/share/wallpapers/`, 3 files, 20 MB. Verified unreferenced. All wallpaper browsing happens inside `themes/*/backgrounds/`.
- `themes/*/generated/*` removed from the git index with `git rm --cached`. The ignore rule already exists and starts working once they are untracked.

### Deduplication

Only pairs inside a single theme, where the duplicate is a visible bug rather than a size issue:

```
ethereal/backgrounds/1-morning-angel.jpg    (== 0-morning-angel.jpg)
ethereal/backgrounds/2-sunset-beach.jpg     (== 1-sunset-beach.jpg)
catppuccin/backgrounds/4-home-fantasy.jpg   (== 0-home-fantasy.jpg)
```

Higher-numbered copy deleted in each case. Both themes still number contiguously from 0 afterwards, so no renumbering is needed. Cross-theme duplicates are left alone: after recompression each is about 390 KB, and the constraint above rules out symlinking them.

### Forced follow-on edits

- `themes/{catppuccin,rosepine}/lockscreen.png` become `.jpg`, so the hardcoded lookup at `theme-switcher.sh:139` becomes extension-tolerant.
- `assets/image{1..5}.png` become `.jpg`, so the three image lines in `README.md` change.

### Incidental fix

All three wallpaper finders match only `*.png` and `*.jpg`. Converting everything to `.jpg` makes `deep-sea/backgrounds/2-deep-sea.webp` and `white/backgrounds/1-sky-castle.jpeg` selectable in the wallpaper picker for the first time.

### Migration

One migration removes `~/.local/share/wallpapers/` from existing installs, but only if its contents still match the three shipped files byte for byte. A user who added their own images there keeps the directory untouched.

### Commit structure

One pull request, three commits, so each is separately reviewable. A single commit that both deletes 127 MB and rewrites 50 images cannot be reviewed by eye.

1. Delete the dead trees and untrack `generated/`.
2. Delete the three intra-theme duplicates.
3. Recompress, add the optimizer, the workflow, `AGENTS.md`, the migration, and the two forced edits.

Each commit message records the checkout size before and after.

## Alternatives considered

**Convention only, no CI guard.** The cleanup delivers the entire 127 MB either way, and the rule is one sentence for a contributor to follow. Rejected because the repo already regrew twice through exactly this gap, once against a `.gitignore` rule that existed and was not enforced. The guard is roughly 40 lines and is the difference between a cleanup and a fix.

**Move backgrounds out of git,** shipping one default theme and fetching the rest from a GitHub release tarball, as `omarchy-theme-bg-install` does. This is the only option that stays small no matter how many themes are added. Rejected for now because the chosen approach already reaches roughly 25 MB, while this one adds a release pipeline, puts a network round trip inside theme switching, and breaks offline installs. Worth revisiting if the theme count grows substantially.

**Symlink-based deduplication.** Rejected on the `find -type f` constraint above, and made largely pointless by recompression, which reduces the 53.5 MB of duplicate bytes to roughly 2 MB on its own.

**Rewriting git history** with `git filter-repo`. Declined by the maintainer. It would take the 177 MiB pack down to roughly 20 MiB, but it force-pushes `main`, permanently breaks the 3 existing forks, invalidates every commit SHA and therefore every commit link in the merged pull requests, and forces everyone with a clone to re-clone.

## Testing

1. `bin/hyprsimple-dev-optimize-images --check` exits 0 on the cleaned tree.
2. Fix mode run twice, second run reports no changes and `git status` is clean.
3. `--check` exits 1 against a deliberately oversized fixture, and names the offending file.
4. `du -sh --exclude=.git --exclude=external .` is under 30 MB.
5. `grep -rn "themes/.*rofi" .local/bin .config` returns nothing, confirming no reader was missed.
6. On the maintainer's live machine: switch to catppuccin, ethereal, rosepine and deep-sea, confirm wallpaper and lockscreen render in each, and confirm the deep-sea webp now appears in the wallpaper picker.
7. Migration dry run: with an extra user file present in `~/.local/share/wallpapers/`, the migration leaves the directory alone. With only the three shipped files, it removes it.
8. CI: the workflow runs and passes on the cleanup pull request itself.

## Open questions

N/A: the two decisions that were open (history rewrite, and which approach) were both resolved before this spec was written, and are recorded in Approach and Alternatives.
