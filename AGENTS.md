# AGENTS.md

Notes for anyone, human or agent, changing scripts or images in this repo.

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
