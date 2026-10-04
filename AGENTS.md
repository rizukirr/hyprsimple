# AGENTS.md

Notes for anyone, human or agent, changing scripts or images in this repo, or
anything an existing install has to receive.

## Script prefixes

Scripts are named by what they do, not where they live. The prefix tells you
the contract:

- `hw-` for a hardware predicate. It prints nothing and returns an exit code
  for use in conditionals (present or absent, supported or unsupported).
- `toggle-` for flipping one setting on or off.
- `theme-` for theme management (switching, listing, applying).
- `hyprsimple-` for a user-facing management command, the kind a user runs
  directly, like `hyprsimple-update` or `hyprsimple-debug`.
- `hyprsimple-dev-` for contributor tooling, not something an end user needs.

The directory matters too, separately from the prefix. `install.sh` copies
everything in `.local/bin/` to the user's `~/.local/bin`, in the loop that
begins `for script in "$DOTFILES_DIR/.local/bin"`, so anything there ships to
every install. Scripts in `bin/` do not ship. They stay in the repo for
contributors only.

The anchor there is a line of code, not a line number. A line number in prose
goes wrong the moment anything above it moves, and nothing announces that, so
cite code you can grep for. `test/suite-hygiene-test.sh` checks that the quoted
line is still in `install.sh` and that this file names no line numbers at all.

## Image policy

`bin/hyprsimple-dev-optimize-images` is the single source of truth for image
size, quality, and format limits in this repo. Do not restate those numbers
here or anywhere else, so the policy and the script cannot drift apart.

CI enforces the policy via `.github/workflows/images.yml`, which runs the
optimizer in check mode on every pull request touching themes or assets. Run
`bin/hyprsimple-dev-optimize-images` yourself before committing new or changed
images, or CI will catch it for you.

## How a change reaches an install

An install is a git checkout at `~/.local/share/hyprsimple`. `hyprsimple-update`, which is `.local/bin/hyprsimple-update.sh`, moves that checkout to a newer commit and then delivers what moved. Merging to main is the first half of shipping a change. The second half is knowing which of the rows below your files fall in.

| What you changed | How it arrives on update | Needs a migration |
|---|---|---|
| `default/hypr/`, `default/dunst/10-hyprsimple.conf` | Read in place through two symlinks, which the `ensure_link` calls re-make on every run, so the pull delivers it. Hyprland applies it at the closing `hyprctl reload`. Nothing restarts dunst here, so its drop-in waits for the next dunst start. | No |
| Scripts in `.local/bin/` | Copied over `~/.local/bin` on every run, whenever they differ. | No |
| `packages.txt`, `aur-packages.txt` | Every listed package that is not installed gets installed. | No to add one, yes to remove one |
| `.config/hypr/themes/templates/` | When the templates' checksum changes, every theme is re-rendered and the active one is delivered and reloaded. | No |
| Any other file under `.config/` | Never overwritten. The run ends by naming the files this pull changed that the user holds a different copy of. | Yes |
| Anything outside the checkout: a service, a udev rule, a file to delete, a link to make | Nothing. | Yes |

Decide the row before you write the change. A setting that lives in `default/hypr/` reaches every install on the next update with no further work. The same setting in `.config/hypr/` reaches nobody until a migration carries it.

### Channels and releases

Which commits an install gets is its channel, and git's own HEAD remembers it. A fresh install sits detached on the newest release tag. A bare `hyprsimple-update` on such an install moves to the newest tag on origin and never to main, so a commit on main reaches nobody on releases until a tag includes it.

A release is two things: a commit that changes `version`, and a tag named `v` plus that version on it. Until both exist, a fix is merged and not shipped.

To try a branch on a real install before it is released, run `hyprsimple-update <branch>`. The install stays on that branch on every later run, and `hyprsimple-update --stable` puts it back on releases. A branch off main carries every unreleased commit on main as well, and their migrations run.

The update refuses to run while the checkout has local changes. Do not test a change by editing files under `~/.local/share/hyprsimple`: push a branch and switch to it.

### Proving delivery without touching a real install

`test/update-channel-test.sh` shows how to run the real update script against a throwaway origin: `HOME` and `HYPRSIMPLE_PATH` redirected, `pgrep` and `hyprctl` stubbed. When the fixture is this repository and not a toy one, stub `pacman` and `sudo` too, and create a marker for every migration, or the run installs packages and runs migrations for real.

## Migrations

A migration is a bash file in `migrations/` that `.local/bin/hyprsimple-migrate.sh` runs once per machine, at the end of an update, with nobody watching. Write one for the two rows above that say yes.

- Create it with `.local/bin/hyprsimple-dev-add-migration.sh`, run from a checkout. The name is a unix timestamp later than every existing name. Migrations run in glob order, so the name is the order on every machine, and a name typed by hand can sort before one that must run first. `test/migration-naming-test.sh` covers this.
- It has no shebang. The runner calls it with `bash`, and CI holds it to the same shellcheck threshold as every other script, with the shell stated.
- The first line is an `echo` saying what it does. The runner announces a migration by its number alone, so that line is how the user learns what ran.
- Exit 0 means done: a marker is written under `~/.local/state/hyprsimple/migrations` and the file never runs on that machine again. Any other status stops the update. On a terminal the user is asked whether to skip it. With no terminal attached it is not skipped, and the next update runs it again from the top.
- Most machines do not need what it does. Test for the condition first and `exit 0` when there is nothing to do, before any `sudo`.
- After exit 0 there is no second chance, so check the result before returning it. After a failure every step runs again, so every step has to be safe to repeat.
- To replace a file the user owns under `~/.config`, call `.local/bin/hyprsimple-refresh-config.sh` with the path. It keeps a backup and shows the diff. A migration that copies over the file directly throws the user's edits away.

`install.sh` marks every migration as done on a fresh install, in the loop that begins `for migration in "$HYPRSIMPLE_PATH/migrations"`. A new install therefore never runs your migration, and has to get the same result from `install.sh` or from the shipped files. Change both, or new installs and updated ones diverge.

A migration that does real work gets a suite of its own that runs it against a fixture, with `HOME` and `HYPRSIMPLE_PATH` set for that one call, as `test/config-migration-test.sh` does. A migration edits whatever `HOME` points at, so a suite that leaves `HOME` alone edits the machine running the tests.

`test/suite-hygiene-test.sh` checks that the `install.sh` loop quoted above is still there.
