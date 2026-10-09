# External plugins: implementation plan

Spec: `docs/specs/2026-10-09-external-plugins-design.md`

Goal: Install independent plugins from GitHub and deliver Muslimtify as a default external plugin on both fresh and existing installations.

Architecture: A Bash manager validates manifests and manages Git checkouts, dependencies and user lifecycle scripts. A Quickshell registry loads shared services and per-monitor widgets and panels. A Lua module reads generated declarative bindings before user overrides.

## Global constraints

- Follow AGENTS.md script prefixes, config ownership, migration creation and fixture isolation rules.
- Plugin code resides under `~/.local/share/hyprsimple-plugins/<id>`, outside the core checkout. Enablement, placement and settings reside under `~/.config/hyprsimple/plugins.json`.
- The installed executable is named `hyprsimple-plugin`. Extend install and update delivery narrowly to ship this extensionless command alongside the existing scripts.
- Validate IDs, manifest types, API compatibility and relative entry paths. Reject path traversal and escaping symlinks before executing plugin code.
- Never overwrite user Hyprland overrides. Keep user overrides after core plugin keybindings and configuration.
- Publish plugin content before shipping a core change that requires downloading it.
- No real package installation, user service modification or changes to the running desktop during automated tests.

## Contract

Choose schemaVersion and apiVersion as integer 1 for the initial contract. The manifest requires `id`, `name` and `version` strings. Optional `entryPoints` contains `service`, `widget` and `panel` relative QML paths. Optional `placement` is `left`, `center` or `right`, defaulting to `left`. Optional `dependencies` contains `packages` and `aur` arrays of validated package names. Optional `lifecycle` contains `enable` and `disable` relative script paths. Optional `bindings` contains objects with `key`, `description` and `action`, where the initial action is `toggle-panel`. Optional `panelAliases` contains strings, with uniqueness checked across installed plugins.

Require at least one QML entry point. Panel bindings and aliases require a panel entry point. Reject unknown fields and unsupported API versions. Reject malformed settings, duplicate IDs, duplicate aliases, symlinked manifests and escaping entry or lifecycle paths. Runtime validation must also reject invalid entries discovered outside the manager.

Config uses `schemaVersion` and a `plugins` object keyed by plugin ID. Each entry has `enabled`, `placement`, `settings` and `commit`. Generate an install-owned bindings JSON file under `~/.local/state/hyprsimple/plugins/bindings.json`. Do not source manifest values as shell or Lua code.

The QML context supplies `pluginId`, `settings`, `theme`, `service`, `screen`, `panelOpen`, `togglePanel()` and `closePanel()`. Widget and panel entry points declare a required `context` property. The service receives a context without per-monitor objects. Shared components use a named `Hyprsimple` QML module on an explicitly configured import path. Test that path from a plugin outside the shell directory before relying on it.

## Task 1: Plugin manager and delivery → verify: manager fixture suite exits 0

Files:

- Create `.local/bin/hyprsimple-plugin`, `test/plugin-manager-test.sh` and `PLUGINS.md`.
- Modify `install.sh`, `.local/bin/hyprsimple-update.sh`, `bootstrap.sh`, `.github/workflows/tests.yml` and affected script-delivery suites.

- [x] Implement direct repository installation, `list`, `validate`, `enable`, `disable`, `update` and `remove`. Use an explicit `--local` install option for local development repositories. Normalize accepted GitHub sources, reject Git options and other transports, and clone with terminal prompts disabled.
- [x] Implement the contract validator with jq and realpath containment checks. Reserve the `hyprsimple.` namespace. Validate every candidate before package or lifecycle work.
- [x] Use flock for mutations, same-directory temporary files for atomic config replacement and staged repository acquisition. Never overwrite an installed plugin on repeated install. Refuse dirty updates and activate only validated candidates. Retain old code and config on failed update, and report lifecycle rollback failures explicitly.
- [x] Install missing declared dependencies with the existing pacman and AUR helper conventions. Enable and verify lifecycle work before recording enablement. Disable UI before stopping background work. Preserve settings and packages on removal, and distinguish an incomplete operation from success.
- [x] Generate declarative enabled-plugin bindings without evaluating plugin text. Refresh a running bar once after a completed operation and request a Hyprland reload only within an active session.
- [x] Deliver the exact extensionless command through install, update and bootstrap without shipping unrelated files from `.local/bin`. Preserve atomic self-replacement in the updater.
- [x] Add fixtures for malformed manifests, traversal, escaping symlinks, unsupported API, invalid URLs, duplicate IDs and aliases, dependency failure, lifecycle failure and retry, dirty updates, failed update rollback, preserved settings, concurrent mutation and command delivery.
- [x] Run `bash test/plugin-manager-test.sh` and relevant install/update/bootstrap suites. Run shellcheck on the manager and changed shell files with the CI severity and exclusions.
- [x] Commit this task.

## Task 2: Shell and Hyprland extension points → verify: loader and binding fixture suites exit 0

Files:

- Create `default/quickshell/plugins/Registry.qml`, `default/quickshell/plugins/PluginSlot.qml`, `default/quickshell/plugins/PluginContext.qml`, `default/quickshell/plugins/Manifest.js`, `default/quickshell/Hyprsimple/qmldir`, `default/hypr/plugins.lua`, `test/plugin-loader-test.sh` and `test/plugin-bindings-test.sh`.
- Modify `default/quickshell/shell.qml`, `default/quickshell/bar/Bar.qml`, `default/hypr/hyprsimple.lua`, `.local/bin/hyprsimple-restart-bar.sh`, `default/hypr/autostart.lua`, `.github/workflows/tests.yml` and `PLUGINS.md`.

- [x] Register the shared QML module on the same import path at login, restart and test invocation. Export the existing Theme, StatusButton, Capsule, PopupPanel and generic components through that module. Keep relative dependencies working and prove an external component can import the module.
- [x] Implement runtime manifest checks and load each enabled service once at shell scope. Create widget and panel contexts per screen. Load external QML dynamically and identify load failures by plugin ID without failing the core shell.
- [x] Add left, center and right slots without moving existing built-in widget groups. Use namespaced panel IDs and connect plugin panel operations to the existing cross-monitor owner behavior. Resolve declared panel aliases for existing IPC callers.
- [x] Read declarative binding JSON in the Lua defaults before user overrides, using the available jq command rather than introducing a JSON dependency. Escape paths and arguments without evaluating plugin values. Ignore malformed entries with a diagnostic.
- [x] Exercise external import resolution and load failure containment through an isolated offscreen Quickshell harness. Verify service sharing, multiple screen contexts, settings, theme changes and panel operations. Record any compositor-dependent coverage limitation.
- [x] Run `bash test/plugin-loader-test.sh`, `bash test/plugin-bindings-test.sh`, `lua test/config-split-test.lua` and affected bar/config suites.
- [x] Commit this task.

## Task 3: External Muslimtify repository → verify: plugin checks and local installation fixture exit 0

Repository: `/tmp/muslimtify-hyprsimple`, remote `https://github.com/muslimtify-org/muslimtify-hyprsimple.git`.

Create `manifest.json`, `Widget.qml`, `Panel.qml`, `Service.qml`, `lib/Model.js`, `views/TodayView.qml`, `views/SettingsView.qml`, `components/PanelHeader.qml`, `components/SettingField.qml`, `components/ErrorLine.qml`, `assets/muslimtify.webp`, `scripts/enable.sh`, `scripts/disable.sh`, `test/model-test.js`, `test/lifecycle-test.sh`, `test/check.sh`, `test/integration-test.sh`, `.github/workflows/tests.yml`, `README.md` and `LICENSE` in that repository.

- [x] Extract the existing model, service, views, components and assets while preserving license attribution. Adapt shared imports to Hyprsimple's public module and use the documented context. Keep prayer-specific constants in the plugin.
- [x] Declare ID `muslimtify`, its AUR dependency, left placement, `SUPER + P` toggle binding and `prayer` panel alias. Preserve current prayer display, settings, schedule error handling and right-click countdown behavior.
- [x] Implement repeatable enable and disable scripts using Muslimtify's daemon commands. Check daemon status after enable and propagate failures. Preserve application settings on disable and removal.
- [x] Move prayer scheduling checks from core ownership to plugin checks. Test model parsing, tomorrow transition, offsets and lifecycle failure/retry with stubs.
- [x] Run `bash test/check.sh` in the plugin checkout. Install from its local Git repository through the real manager into an isolated home, verify load behavior and disable/remove behavior, and confirm application settings remain unchanged.
- [x] Run the core image optimizer in check mode on the extracted asset, using its actual supported CLI discovered during execution.
- [x] Commit and push the plugin contents to the user-supplied repository. Verify the published commit and manifest before core migration or installer depends on them.

## Task 4: Default installation and migration → verify: migration and fresh-install fixture suites exit 0

Files:

- Modify `install.sh`, `aur-packages.txt`, `.local/bin/hyprsimple-muslimtify.sh`, `default/quickshell/shell.qml`, `default/quickshell/bar/Bar.qml`, `default/quickshell/theme/Theme.qml` and `default/hypr/bindings/system.lua`.
- Remove extracted files under `default/quickshell/muslimtify/`, `default/quickshell/bar/PrayerButton.qml` and `default/quickshell/panels/PrayerPanel.qml`.
- Create a migration with `.local/bin/hyprsimple-dev-add-migration.sh --no-edit`. The returned path is `migrations/1791551522.sh`.
- Create `test/plugin-migration-test.sh`, `test/plugin-default-install-test.sh` and shared fixture helper `test/fixtures/plugin-environment.bash`.
- Modify `.github/workflows/tests.yml`, `README.md`, `test/bar-test.sh`, `test/notify-bar-test.sh`, `test/aur-helper-test.sh`, `test/muslimtify-and-dns-test.sh`, `test/panel-keybinds-test.sh`, `test/plugin-loader-test.sh`, `test/readme-keybindings-test.sh` and other suites discovered to depend on the removed paths.

- [x] Remove core-owned Muslimtify QML and unconditional package/daemon setup. Invoke the external plugin manager after helper delivery and before starting the bar. Report installation failure with a retry command through the installer's failure reporting.
- [x] Use direct plugin manager commands for Muslimtify management. Task 6 records the approved helper and shell alias removal.
- [x] Write the generated migration with an explanatory echo as its first line and no shebang. Detect installed Muslimtify before any privileged work. Skip absent installations and respect an already installed plugin's disabled state. Install and enable the external plugin for installations retaining the integration. Verify manifest registration, enablement and daemon success before returning 0.
- [x] Test the real migration runner with isolated homes and installed/absent cases, repeated runs, already disabled plugin, preserved settings, network failure, daemon failure and retry. Assert failed migrations receive no completion marker.
- [x] Test the default installer path against the local plugin origin with all package/service commands stubbed. Ensure migration markers on a fresh install do not replace direct plugin setup.
- [x] Update old assertions to test the new ownership boundary. Keep unrelated DNS and historical migration coverage intact. Run new suites, affected old suites and migration naming/hygiene checks.
- [x] Commit this task.

## Task 5: Complete delivery verification → verify: required CI checks and isolated updater integration exit 0

Files:

- Create `test/plugin-update-delivery-test.sh` and modify `test/suite-hygiene-test.sh` to permit only the explicitly fetched, pinned historical updater fixture.
- Modify `.github/workflows/tests.yml` and `PLUGINS.md` with final verification and author instructions.
- Repair `migrations/1791551522.sh` and extend `test/fixtures/plugin-environment.bash` and `test/plugin-migration-test.sh` for first-update bootstrap delivery.

Prerequisite: the pre-delivery updater from `9c9ba72` copies only `.sh` and `.fish` files and does not re-execute after atomic self-replacement. The migration must atomically deliver the executable manager from the checkout before its absent-Muslimtify skip. A missing source must fail without a marker or replacing an existing manager. Verify missing-home-manager cases with and without Muslimtify, repeatability, and missing-source retry. Use the actual historical updater in the delivery regression.

- [x] Run the real updater against a throwaway core origin and home, with pacman, sudo, pgrep, hyprctl, Muslimtify and services stubbed. Mark every migration except the new one complete. Verify command delivery, migrated plugin registration, preserved settings and core reload behavior.
- [x] Verify a later core update leaves external plugin commits and settings unchanged. Verify explicit plugin update uses its own origin and restores previous code on failed activation.
- [x] Run the shellcheck commands and all shell/Lua suites required by `.github/workflows/tests.yml`. Include the extensionless manager in lint explicitly. Run the plugin repository's checks independently.
- [x] Document manifest fields, author workflow, trusted-code execution, installation, default Muslimtify behavior, manager commands, updates, removal and failure recovery. Record compositor-dependent checks that require a real session.
- [x] Commit this task and report tested commands, published plugin commit, core commits and outstanding session verification. Do not tag a release or alter the real install.

### Task 5 verification evidence

All 86 workflow-registered shell/Lua checks have final exit status 0. The initial update-channel socket and screenshot/battery systemd-validation failures passed after approved escalation, using fixture state without live desktop changes. Hygiene initially rejected an unprovided history read and unchecked clone results. The final regression reads only the explicitly fetched, pinned updater and asserts cloned fixture content exists. The hygiene audit preserves its checks for other history reads.

Both CI shellcheck commands exited 0 with `--severity=style --exclude=SC2016`, including the extensionless manager, all shell suites and Bash fixtures, and migrations with `--shell=bash`. `git diff --check` exited 0. `HYPRSIMPLE_SOURCE=/home/rizukirr/Projects/hyprsimple bash test/check.sh` in `/tmp/muslimtify-hyprsimple` exited 0 at published commit `0a8fa79a7696662c7d2a2e4c68979cb50eda628b`, covering the model, lifecycle, manifest, local manager integration, actual QML components and image policy.

The per-suite attempt statuses below retain initial failures and successful reruns. Detailed local logs are under `/tmp/hyprsimple-task5-results`. These are local results, not a remote CI verdict. Real compositor placement, focus and monitor behavior remain session checks documented in `PLUGINS.md`. The parent independently performs final verification. No core push, release or live install change was performed.

```text
exit command
0 bash test/plugin-loader-test.sh
0 bash test/plugin-migration-test.sh
0 bash test/plugin-default-install-test.sh
0 bash test/plugin-update-delivery-test.sh
0 bash test/plugin-bindings-test.sh
0 bash test/plugin-manager-test.sh
0 bash test/install-copy-test.sh
0 lua test/config-split-test.lua
0 bash test/config-migration-test.sh
0 bash test/config-realworld-test.sh
0 bash test/shallow-install-test.sh
0 bash test/theme-refresh-test.sh
0 bash test/hypr-conf-split-test.sh
0 bash test/broken-override-test.sh
0 bash test/named-paths-test.sh
0 bash test/keyboard-backlight-test.sh
0 bash test/notify-bar-test.sh
0 bash test/icon-themes-test.sh
0 bash test/hyprsunset-config-test.sh
0 bash test/live-wallpaper-persistence-test.sh
0 bash test/logout-test.sh
0 bash test/bluetooth-toggle-test.sh
0 bash test/btop-theme-test.sh
0 bash test/config-ownership-test.sh
0 bash test/cursor-theme-test.sh
0 bash test/theme-picker-test.sh
0 bash test/toggle-scripts-test.sh
1 bash test/update-channel-test.sh
0 bash test/update-self-replace-test.sh
0 bash test/template-delivery-test.sh
0 bash test/config-drift-report-test.sh
0 bash test/template-cleanup-test.sh
0 bash test/template-autorender-test.sh
0 bash test/package-install-test.sh
0 bash test/aur-helper-test.sh
0 bash test/unattended-install-test.sh
0 bash test/audio-autoswitch-test.sh
0 bash test/notification-idiom-test.sh
1 bash test/screenshot-and-battery-test.sh
0 bash test/screen-record-test.sh
0 bash test/setup-network-test.sh
0 bash test/hybrid-gpu-env-test.sh
0 bash test/nvidia-install-test.sh
0 bash test/intel-video-test.sh
0 bash test/hw-predicate-test.sh
0 bash test/untested-script-bugs-test.sh
0 bash test/muslimtify-and-dns-test.sh
0 bash test/launched-programs-test.sh
0 bash test/vars-key-removal-test.sh
0 bash test/generated-cleanup-test.sh
0 bash test/committed-symlinks-test.sh
0 bash test/confirm-before-delete-test.sh
0 bash test/bar-test.sh
0 bash test/picker-panels-test.sh
0 bash test/shell-init-test.sh
0 bash test/wifi-test.sh
0 bash test/update-channel-test.sh (escalated)
0 bash test/screenshot-and-battery-test.sh (escalated)
0 bash test/debug-report-test.sh
0 bash test/migration-naming-test.sh
0 bash test/readme-keybindings-test.sh
0 bash test/keybinding-viewer-test.sh
0 bash test/panel-keybinds-test.sh
0 bash test/wallpaper-keys-migration-test.sh
0 bash test/ghostty-theme-test.sh
0 bash test/default-links-test.sh
0 bash test/window-rules-test.sh
0 bash test/install-backup-test.sh
0 bash test/firewall-test.sh
0 bash test/removed-files-test.sh
0 bash test/env-block-test.sh
0 bash test/theme-delivery-test.sh
0 bash test/nightlight-test.sh
0 bash test/hyprsunset-service-test.sh
0 bash test/required-helpers-test.sh
0 bash test/gtk-settings-test.sh
0 bash test/migration-runner-test.sh
0 bash test/capture-panels-test.sh
0 bash test/clipboard-panel-test.sh
0 bash test/rofi-removal-test.sh
0 bash test/notifications-test.sh
0 bash test/network-setup-test.sh
0 bash test/wallpaper-ipc-test.sh
0 bash test/rosepine-wallpaper-test.sh
0 bash test/theme-catalogue-test.sh
0 bash test/gpu-pin-migration-test.sh
0 bash test/thermald-test.sh
1 bash test/suite-hygiene-test.sh
1 bash test/suite-hygiene-test.sh (pinned fixture audit)
0 bash test/plugin-update-delivery-test.sh (full pinned hash)
0 bash test/suite-hygiene-test.sh (final)
0 bash test/plugin-update-delivery-test.sh (clone assertions)
```

## Self-review

The manager, runtime, external plugin and delivery tasks together cover the approved spec. The migration filename is deliberately obtained from the repository helper. All newly named files and contract values are implementation choices. Existing paths and checks were observed in this checkout. The plugin publication precedes core dependency activation, and every machine-changing test uses fixture state and stubs.

## Task 6: Remove Muslimtify compatibility scripts → verify: affected isolated suites and both CI shellcheck versions exit 0

Files: `.local/bin/hyprsimple-muslimtify.sh` (delete), `.local/bin/bashrc.sh`, `.local/bin/zsh.sh`, `.local/bin/fish.fish`, `install.sh`, `migrations/1791551522.sh`, generated `migrations/1791554376.sh`, `README.md`, `PLUGINS.md`, `test/fixtures/plugin-environment.bash`, `test/plugin-migration-test.sh`, `test/plugin-default-install-test.sh`, `test/plugin-update-delivery-test.sh`, `test/muslimtify-cleanup-test.sh`, `test/muslimtify-and-dns-test.sh`, `test/aur-helper-test.sh`, `test/install-backup-test.sh`, `test/notify-bar-test.sh`, `.github/workflows/tests.yml`, this plan and `docs/specs/2026-10-09-external-plugins-design.md`.

- [x] Delete the helper and all three shipped shell aliases. Use the exact home manager and official repository URL in the installer and existing unreleased migration. Preserve atomic bootstrap, disabled intent, pending retry and daemon verification. Installer repeated setup enables an existing plugin without cloning. Test healthy repeated setup, stopped daemon recovery and download failure retry. Report install versus enable recovery, including explicit daemon install when enable is a no-op.
- [x] Remove only the obsolete home helper in the installer before marking migrations complete and in the generated cleanup migration. Seed stale helper files for fresh and repeated installer runs. Verify absence after deletion. Test absent, repeat, symlink and failed deletion cases in an isolated suite registered in CI. Preserve user configuration, plugin settings, packages and services.
- [x] Update documentation and affected fixtures. Prove fresh helper absence and real updater alias delivery and helper cleanup, marking every unrelated migration complete. Preserve historical migration, DNS and yazi coverage and external lifecycle scripts.
- [x] Run `MUSLIMTIFY_PLUGIN_FIXTURE=/tmp/muslimtify-hyprsimple bash test/<suite>.sh` for plugin-migration, plugin-default-install, plugin-update-delivery, muslimtify-cleanup, muslimtify-and-dns, aur-helper, install-backup, notify-bar, shell-init, migration-naming and suite-hygiene. Run the CI style shellcheck commands with SC2016 excluded and zsh excluded using both `/tmp/hyprsimple-shellcheck09/shellcheck-v0.9.0/shellcheck` and current 0.11. Run `git diff --check` and audit active compatibility references with `rg --hidden`. Commit only after these pass. Do not push or touch real installs.

Task 6 verification: all eleven named suites exited 0. Both complete CI shellcheck commands passed with versions 0.9.0 and 0.11.0. `git diff --check` passed. The pinned fixture at `/tmp/muslimtify-hyprsimple` has commit `0a8fa79a7696662c7d2a2e4c68979cb50eda628b`. The supplied alternate path was absent. Active compatibility-reference audit found only deliberate cleanup paths and regression assertions. Real updater delivery preserved settings and verified removal of the helper and all shell aliases. Installer fixtures exercised actual manager calls through the reload anchor, including stale helper cleanup before markers, healthy repeated setup without acquisition, stopped daemon reporting, activation retry and network failure retry. Full repository suites and GitHub CI remain for the parent. No external repository, real install, package or service was modified. No push was performed.
