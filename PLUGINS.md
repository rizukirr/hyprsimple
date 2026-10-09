# External plugins

`hyprsimple-plugin owner/repo` or `hyprsimple-plugin https://github.com/owner/repo.git` downloads, validates, installs dependencies and enables a plugin. Only HTTPS GitHub repositories and owner/repo shorthand are accepted. Git authentication prompts are disabled. Review the repository first: lifecycle scripts execute as your user and dependencies can request privileged package installation. A valid manifest is a data contract, not a security sandbox for plugin code.

Plugins live at `~/.local/share/hyprsimple-plugins/<id>`, outside the core Git checkout. `HYPRSIMPLE_PLUGIN_ROOT` overrides this location for development and isolated tests. Storage inside the core checkout is rejected. The manager serializes operations with `flock` and stages repository acquisition beside the plugin root.

Use these commands:

```sh
hyprsimple-plugin install owner/repo
hyprsimple-plugin install --local /absolute/path/to/repository
hyprsimple-plugin list
hyprsimple-plugin validate
hyprsimple-plugin validate example
hyprsimple-plugin validate /path/to/plugin/repository
hyprsimple-plugin enable example
hyprsimple-plugin disable example
hyprsimple-plugin update example
hyprsimple-plugin remove example
```

Local development installation clones committed content, rather than linking or copying uncommitted files. Installation never overwrites an existing ID. Update refuses dirty installed repositories and validates the candidate before dependency or lifecycle work. Updating a local installation reads its local origin. Failed activation restores the old code and configuration and reports any failure to restart the old lifecycle. Declared packages stay installed after failure or removal.

The repository root must contain a regular, non-symlinked `manifest.json`:

```json
{
  "schemaVersion": 1,
  "apiVersion": 1,
  "id": "example",
  "name": "Example plugin",
  "version": "1.0.0",
  "entryPoints": {"panel": "Panel.qml"},
  "placement": "left",
  "dependencies": {"packages": [], "aur": []},
  "lifecycle": {"enable": "enable.sh", "disable": "disable.sh"},
  "bindings": [{"key": "SUPER, P", "description": "Open example", "action": "toggle-panel"}],
  "panelAliases": ["example"]
}
```

The two version fields must be integer 1. IDs start with a lowercase letter and contain lowercase letters, numbers and dot or hyphen separated segments. The `hyprsimple.` namespace is reserved. `id`, `name`, `version` and at least one QML entry point are required. Entry points can be `service`, `widget` or `panel`. Paths must be relative, must contain no empty, dot or parent segments and must resolve to regular files within the repository. Internal symlinks are allowed for entries and lifecycle scripts. Escaping symlinks and symlinked manifests are rejected.

Optional placement is `left`, `center` or `right`, with `left` as the default. Dependencies contain `packages` and `aur` arrays of package names. Missing official packages use pacman. Missing AUR packages use the shared helper selection and unattended flags. Package presence is checked again after installation.

Optional lifecycle `enable` and `disable` paths run with Bash from the plugin directory, with `HYPRSIMPLE_PLUGIN_ID` supplied. Each script must verify its own work and return zero only on success. Scripts must be safe to repeat because failures can be retried, including partially completed enablement. Enablement is recorded only after successful enable lifecycle execution. A failed initial activation keeps the installed plugin disabled so `enable` can be retried. Disable publishes disabled configuration and bindings and refreshes the running bar before stopping background work. A failed disable or removal reports an incomplete operation and leaves code available for retry. Removal preserves disabled configuration, settings and packages.

Bindings require `key`, `description` and the action `toggle-panel`. Panel bindings and aliases require a panel entry point. Aliases are unique across installed plugins. Unknown fields, duplicate fields and IDs, malformed configuration, unsupported versions and invalid paths are rejected by management and runtime validation. Manifest values are handled as JSON data and never sourced as shell or Lua.

Configuration lives at `~/.config/hyprsimple/plugins.json` with `schemaVersion: 1` and a `plugins` object keyed by ID. Every entry contains boolean `enabled`, `placement`, an object `settings` and the installed Git `commit`. Configuration replacement uses a temporary file in the same directory and an atomic rename. The manager preserves settings and placement through updates, removal and reinstall. Enabled bindings are generated at `~/.local/state/hyprsimple/plugins/bindings.json` as `{"schemaVersion":1,"bindings":[...]}`, with `pluginId` added to each binding. The manager refreshes a running bar once per completed operation and requests Hyprland reload only in an active session. It does not modify user Hyprland overrides.

This task provides repository management, lifecycle execution and manifest validation. QML loading and activation are delivered by the later shell loader task. The planned QML context supplies `pluginId`, `settings`, `theme`, `service`, `screen`, `panelOpen`, `togglePanel()` and `closePanel()`. Widgets and panels declare a required `context` property. Services receive a context without per-monitor objects. The planned shared module is named `Hyprsimple`, with its external import path verified by the loader task.

Run `bash test/plugin-manager-test.sh` for isolated manager fixtures. Tests redirect HOME and plugin storage and stub package and desktop commands.
