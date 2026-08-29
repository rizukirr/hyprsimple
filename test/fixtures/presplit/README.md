# Pre-split config fixture

`.config/hypr` exactly as hyprsimple shipped it at commit `30291d9`, the last
commit before the config defaults split in PR #22.

`test/config-realworld-test.sh` migrates a copy of this and loads the result, to
prove a real user's config survives the migration.

**Do not edit these files.** They are a frozen record of what users had, not a
config anyone runs. Editing them makes the test assert against something nobody
ever installed. The suite checks `looknfeel.lua` still has more than 40 live
lines, which catches the most likely accident.
