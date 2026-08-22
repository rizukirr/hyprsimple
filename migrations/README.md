# Migrations

Each file here is a one-shot script that brings an **already installed** machine
in line with a change made in this repo. They exist because `install.sh` only
runs once — without migrations, a fix to a default config never reaches anyone
who already installed hyprsimple.

## Rules

- Name the file after a unix timestamp so it sorts in the order it was written.
  `hyprsimple-dev-add-migration.sh` does this for you (it uses the timestamp of
  your last commit).
- Migrations are run with `bash`, not sourced. No shebang needed; permissions
  stay `0644`.
- Start with an `echo` describing what the migration does — the runner prints it
  above your output.
- **Make it idempotent.** A migration may be re-run after being skipped, so
  guard every edit with a `grep` or an existence check.
- Use `$HYPRSIMPLE_PATH` to reach the repo; the runner exports it.
- To replace a default config wholesale, call
  `hyprsimple-refresh-config.sh <path>` — it backs the user's version up and
  prints the diff, instead of silently overwriting.

## Creating one

```bash
# from a hyprsimple checkout, after committing your change
~/.local/bin/hyprsimple-dev-add-migration.sh
```

## How state is tracked

A migration that succeeds leaves a marker in
`~/.local/state/hyprsimple/migrations/`. One the user chose to skip after a
failure lands in `.../migrations/skipped/`. Fresh installs get every marker
created up front by `install.sh`, so new users never run historical migrations.
