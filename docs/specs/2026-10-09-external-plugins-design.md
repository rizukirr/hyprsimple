---
title: external plugins
date: 2026-10-09
status: approved
---

# External plugins: design

## Problem

Quickshell creates its services, bar widgets and panels directly in the shipped shell. Independent projects cannot install a widget without changing Hyprsimple. Muslimtify's optional executable has a mandatory UI implementation in the core repository.

## Goals

- `hyprsimple-plugin https://github.com/muslimtify-org/muslimtify-hyprsimple.git` installs and enables the external Muslimtify integration, including its dependency and daemon.
- Fresh installs install this external plugin by default. Muslimtify's UI, model, assets and lifecycle scripts live in its separate repository.
- Existing installs with Muslimtify retain their prayer widget, settings and daemon through an idempotent migration. Installs without Muslimtify do not acquire it during migration.
- Authors can declare a shared QML service, bar widget, panel and optional user lifecycle commands through a documented manifest without editing core files.
- Users can list, enable, disable, update, remove and validate plugins. Disabling removes the UI and stops plugin-managed background work. Removing preserves application settings and installed packages.
- Plugin load failures identify the plugin and leave built-in widgets working. Invalid or incompatible manifests never activate.

## Non-goals

- Converting other built-in widgets to plugins, replacing the full bar or building a marketplace.
- Automatically updating external repositories during `hyprsimple-update`.
- A security sandbox for QML or shell lifecycle commands.
- Publishing a Hyprsimple release as part of implementation.

## Constraints

- Follow AGENTS.md script prefixes, config ownership, migration creation and fixture isolation rules.
- Plugin code resides under `~/.local/share/hyprsimple/plugins/<id>`, outside the core checkout. Enablement, placement and settings reside under `~/.config/hyprsimple/plugins.json`.
- The installed executable is named `hyprsimple-plugin`. Extend install and update delivery narrowly to ship this extensionless command alongside the existing scripts.
- Accept HTTPS GitHub repository URLs and `owner/repository` shorthand. Local repository sources are available through an explicit development option for isolated tests.
- Validate IDs, manifest types, API compatibility and relative entry paths. Reject path traversal and escaping symlinks before executing plugin code.
- Lifecycle commands run as the user. Declared package dependencies use the existing package and AUR helper conventions. Validate before installing dependencies or invoking lifecycle commands.
- Never overwrite user Hyprland overrides. Keep user overrides after core plugin keybindings and configuration.
- Publish plugin content before shipping a core change that requires downloading it.

## Approach

Use a small manifest-based extension system. The user requested an external Muslimtify repository and confirmed that fresh installs should install it by default. Keep other built-in widgets unchanged.

A manifest at the repository root declares a schema version, plugin API version, ID, name, version, optional package dependencies, optional service/widget/panel entry paths, default bar placement, optional keybindings and optional enable/disable lifecycle script paths. Document the exact fields together with the validator during implementation. Use JSON and the existing jq dependency for shell operations.

One plugin manager handles repository acquisition, validation, dependency installation, lifecycle operations and atomic config writes. Installation stages and validates the clone before activation. It records the installed commit. Updates refuse dirty repositories, stage and validate the candidate, and retain the previous version when activation fails. Repeated installation does not overwrite an existing plugin. Failures exit nonzero and retain enough state for a safe retry. A manager lock prevents concurrent mutations.

A Quickshell registry reads enabled manifests and loads shared services once per shell. Each monitor gets its own widget and panel instances through explicit bar slots. Expose a narrow versioned context with theme values, plugin settings, its service, screen and panel operations. Plugin-local imports resolve within its own repository. Expose documented shared UI components through a stable import path, with a loading test proving external import resolution.

Panels use the existing one-open-panel behavior across monitors. Plugin panel IDs are namespaced. Keep `SUPER + P` and the existing prayer panel IPC route working for Muslimtify through an explicit compatibility route. Core Hyprland defaults load declared enabled-plugin bindings before user overrides and reload after plugin changes.

Extract the Muslimtify service, model, views, assets, prayer widget and panel into https://github.com/muslimtify-org/muslimtify-hyprsimple.git. Move prayer-specific layout values out of the core theme. Its enable lifecycle registers and checks the daemon, and its disable lifecycle unregisters it. Preserve `~/.config/muslimtify/config.json`. Existing add/remove aliases delegate to the plugin manager instead of deleting packages.

Remove Muslimtify from the core AUR package list and installer daemon setup. The installer invokes the plugin manager after helper delivery and before the first bar startup. A generated migration installs the external integration only where Muslimtify was already present, and verifies successful registration before returning success. Failed downloads or setup are reported and retryable rather than silently marking the migration complete.

## Alternatives considered

- External plugins alongside existing built-ins, recommended. This provides the requested author workflow and proves it with Muslimtify while keeping the change focused.
- Convert every built-in component to a plugin. This makes all UI use the same contract but expands the migration and compatibility surface beyond the requested first integration.
- Launch every plugin as a separate Quickshell process. This isolates process failures but makes integrated bar placement, shared services and coordinated panels harder to deliver.

## Testing

Use throwaway Git origins and isolated fixture homes for manager installation, repeat installation, validation, dependency failures, lifecycle failures, dirty updates, failed updates, disable, enable and removal. Stub pacman, sudo, AUR helpers, systemctl, muslimtify, pgrep and hyprctl so tests do not change the running machine.

Use Quickshell smoke tests with isolated state and supported headless execution to verify external imports, service sharing, widget loading, panel activation, theme propagation and failure containment. If the environment cannot exercise a compositor-dependent behavior, record the limitation and provide a reproducible session check rather than claiming it passed.

Test the real migration against installed and absent Muslimtify fixtures, including failure and retry. Test fresh installer delivery and the real updater against a throwaway origin with every other migration marked complete. Add relevant suites to CI, update affected existing tests and run the required shellcheck and Lua/config checks.

The plugin repository carries its own manifest and model checks. Test installation from its local Git checkout before publishing, then verify the published repository and recorded commit.

## Open questions

N/A: The user supplied the external repository and confirmed default installation. Exact manifest fields and shared UI import mechanics must be settled and tested in the implementation plan.
