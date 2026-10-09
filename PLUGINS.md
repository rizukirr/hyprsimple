# External plugins

`hyprsimple-plugin owner/repo` or `hyprsimple-plugin https://github.com/owner/repo.git` downloads, validates, installs dependencies and enables a plugin. Only HTTPS GitHub repositories and owner/repo shorthand are accepted. Git authentication prompts are disabled. Review the repository first: lifecycle scripts execute as your user and dependencies can request privileged package installation. A valid manifest is a data contract, not a security sandbox for plugin code.

Plugins live at `~/.local/share/hyprsimple-plugins/<id>`, outside the core Git checkout. `HYPRSIMPLE_PLUGIN_ROOT` overrides this location for development and isolated tests. Storage inside the core checkout is rejected. The manager serializes operations with `flock` and stages repository acquisition beside the plugin root.

Use these commands:

```sh
hyprsimple-plugin owner/repo
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
  "bindings": [{"key": "SUPER + P", "description": "Open example", "action": "toggle-panel"}],
  "panelAliases": ["example"]
}
```

The two version fields must be integer 1. IDs start with a lowercase letter and contain lowercase letters, numbers and dot or hyphen separated segments. The `hyprsimple.` namespace is reserved. `id`, `name`, `version` and at least one QML entry point are required. Entry points can be `service`, `widget` or `panel`. Paths must be relative, must contain no empty, dot or parent segments and must resolve to regular files within the repository. Internal symlinks are allowed for entries and lifecycle scripts. Escaping symlinks and symlinked manifests are rejected.

Optional placement is `left`, `center` or `right`, with `left` as the default. Dependencies contain `packages` and `aur` arrays of package names. Missing official packages use pacman. Missing AUR packages use the shared helper selection and unattended flags. Package presence is checked again after installation.

Optional lifecycle `enable` and `disable` paths run with Bash from the plugin directory, with `HYPRSIMPLE_PLUGIN_ID` supplied. Each script must verify its own work and return zero only on success. Scripts must be safe to repeat because failures can be retried, including partially completed enablement. Enablement is recorded only after successful enable lifecycle execution. A failed initial activation keeps the installed plugin disabled so `enable` can be retried. Disable publishes disabled configuration and bindings and refreshes the running bar before stopping background work. A failed disable or removal reports an incomplete operation and leaves code available for retry. Removal preserves disabled configuration, settings and packages.

Bindings require `key`, `description` and the action `toggle-panel`. Panel bindings and aliases require a panel entry point. Aliases are unique across installed plugins. Unknown fields, duplicate fields and IDs, malformed configuration, unsupported versions and invalid paths are rejected by management and runtime validation. Manifest values are handled as JSON data and never sourced as shell or Lua.

Configuration lives at `~/.config/hyprsimple/plugins.json` with `schemaVersion: 1` and a `plugins` object keyed by ID. Every entry contains boolean `enabled`, `placement`, an object `settings` and the installed Git `commit`. Configuration replacement uses a temporary file in the same directory and an atomic rename. The manager preserves settings and placement through updates, removal and reinstall. Enabled bindings are generated at `~/.local/state/hyprsimple/plugins/bindings.json` as `{"schemaVersion":1,"bindings":[...]}`, with `pluginId` added to each binding. The manager refreshes a running bar once per completed operation and requests Hyprland reload only in an active session. It does not modify user Hyprland overrides.

The shell validates manifests and configuration independently at startup, including canonical filesystem containment and duplicate fields. Enabled services load once at shell scope. A failed declared service skips that plugin's widget and panel. Other QML load failures report the plugin ID and leave the core shell running. Restart the bar after manual edits to plugin code or configuration.

Every entry point declares `required property var context`. The context supplies `pluginId`, `settings`, `theme`, `service`, `screen`, `panelOpen`, `togglePanel()` and `closePanel()`. Services receive no screen or bar. Widgets and panels receive a separate context on each monitor and the same shared service. Panel IDs are `plugin:<id>` and use the existing cross-monitor owner behavior. Declared aliases resolve for callers of `qs -p <shell-directory> ipc call bar toggle <alias>`. Placement slots sit beside the existing built-in groups. Invisible widgets take no slot space.

External QML uses `import Hyprsimple`. Login and restart add `default/quickshell` to `QML_IMPORT_PATH`. For manual launches, use `QML_IMPORT_PATH="$HYPRSIMPLE_PATH/default/quickshell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" qs -p "$HYPRSIMPLE_PATH/default/quickshell"`. The module exports the existing Theme singleton, Capsule, StatusButton, PopupPanel and generic components, including StyledText, TextField, SectionLabel, Meter, IconButton, TextButton, Segmented, Toggle, Slider, Dropdown, Icon, CAnim and Anim. It references core files without copying them.

```qml
import QtQuick
import Hyprsimple

Capsule {
    required property var context
    StatusButton {
        label: context.settings.label ?? "Example"
        active: context.panelOpen
        onClicked: context.togglePanel()
    }
}
```

A panel using `PopupPanel` supplies `bar: context.bar`, `anchorItem: context.anchorItem` and `name: context.panelId`. Those helpers connect its positioning and dismissal to the core panel system. Bindings use Hyprland Lua key syntax, for example `SUPER + P`. The Lua defaults read the generated JSON with jq before user overrides, validate each binding, and pass quoted arguments to IPC without evaluating manifest values.

Run `bash test/plugin-loader-test.sh` with Quickshell installed and `bash test/plugin-bindings-test.sh` for isolated runtime and binding fixtures. The loader uses real Quickshell with the offscreen Qt platform and isolated HOME, XDG directories and D-Bus address. It verifies external import resolution, service sharing, contexts, live theme changes, panel operations and load failure containment. Offscreen tests model monitor ownership but cannot exercise PopupPanel's layer-shell window, compositor focus or physical monitor placement. CI runs the loader in an Arch container with Quickshell and jq installed.

Run `bash test/plugin-manager-test.sh` for isolated manager fixtures. Tests redirect HOME and plugin storage and stub package and desktop commands.

## Default Muslimtify plugin

Fresh installs enable `muslimtify-org/muslimtify-hyprsimple` by default and install its declared Muslimtify dependency. The published plugin commit used by delivery verification is `0a8fa79a7696662c7d2a2e4c68979cb50eda628b`. Its widget sits on the left by default, `SUPER + P` toggles its panel, and `prayer` is its IPC alias.

Migration `migrations/1791551522.sh` atomically delivers the executable manager before checking whether Muslimtify is present, so the first update also works with an updater that only copies `.sh` and `.fish` files. It registers the external plugin on existing installs where Muslimtify is present. It preserves `~/.config/muslimtify/config.json`, plugin settings and placement, and user Hyprland bindings. An already installed, deliberately disabled plugin stays disabled. When Muslimtify is absent, the migration completes without downloading it.

```sh
hyprsimple-plugin muslimtify-org/muslimtify-hyprsimple
muslimtify-add
muslimtify-remove
hyprsimple-plugin update muslimtify
```

`muslimtify-add` installs or enables the external plugin and verifies daemon status. `muslimtify-remove` removes its code and disables its registration while retaining settings and installed packages. These compatibility commands use the same manager as other plugins.

Core updates deliver the manager and runtime, but leave external plugin commits and settings unchanged. Use `hyprsimple-plugin update <id>` to follow that plugin's own origin. Core API compatibility is checked before activation. Review plugin changes before updating because QML and lifecycle scripts execute trusted code as your user.

If initial activation fails, the plugin remains installed and disabled. Fix the reported cause and retry `hyprsimple-plugin enable <id>`. If the Muslimtify migration reports a stopped daemon, run `muslimtify daemon install && muslimtify-add`, then retry `hyprsimple-update`. Failed migrations retain their pending intent and get no completion marker. If update activation fails, the manager restores the previous code, settings and bindings and tries to reactivate the previous lifecycle. Resolve any reported rollback failure before retrying. A failed disable or removal leaves code available for another attempt. Dirty installed repositories must be committed, stashed or cleaned before an update.

## Author workflow

Create a repository with the complete manifest above and these files for its declared entry points and lifecycle scripts. `Panel.qml` can use the shared module directly:

```qml
import QtQuick
import Hyprsimple

PopupPanel {
    required property var context
    bar: context.bar
    anchorItem: context.anchorItem
    name: context.panelId
    panelWidth: 320
    StyledText {
        text: context.settings.label ?? "Example panel"
    }
}
```

For the manifest's `enable.sh` and `disable.sh`, a plugin with no background work can use this content in each file:

```bash
#!/bin/bash
set -euo pipefail
exit 0
```

Add actual background setup and verified, repeatable cleanup only when your plugin requires it. Commit all declared files before installing locally:

```sh
git init -b main
git add manifest.json Panel.qml enable.sh disable.sh
git -c user.name="Plugin author" -c user.email="author@example.com" commit -m "Add example plugin"
hyprsimple-plugin validate "$PWD"
hyprsimple-plugin install --local "$PWD"
hyprsimple-plugin list
hyprsimple-plugin disable example
hyprsimple-plugin enable example
```

Edit and commit the source repository, then run `hyprsimple-plugin update example` to test acquisition and activation from that local origin. Test invalid manifests and lifecycle failure recovery as well as successful loading. After publishing your repository, users install with `hyprsimple-plugin owner/repo`. Choose a unique ID and panel aliases. Declare only the dependencies and entry points you use, and support API 1 until the core provides another API.

## Delivery verification

CI fetches the published Muslimtify commit once as a pinned fixture and supplies its checkout through `MUSLIMTIFY_PLUGIN_FIXTURE`. Tests never fetch from the network. Run the delivery suites locally with that same checkout:

```sh
export MUSLIMTIFY_PLUGIN_FIXTURE=/path/to/pinned/muslimtify-hyprsimple
bash test/plugin-default-install-test.sh
bash test/plugin-migration-test.sh
bash test/plugin-update-delivery-test.sh
```

The updater suite uses a throwaway core origin and HOME, marks all earlier migrations complete, and runs the actual pre-delivery updater from `9c9ba72` and the new migration. Package, service and compositor commands are stubbed. It verifies command delivery, preserved settings, core reload, independent plugin updates and failed activation rollback. The extensionless manager is explicitly included in CI shellcheck alongside scripts, fixtures and migrations.

Run the plugin repository's own checks separately, including its actual service, widget, panel and views through the offscreen integration harness:

```sh
cd /path/to/muslimtify-hyprsimple
HYPRSIMPLE_SOURCE=/path/to/hyprsimple bash test/check.sh
```

A real Hyprland session must still verify physical panel placement on each monitor, cross-monitor panel ownership, keyboard focus, outside-click dismissal, Escape, the `SUPER + P` binding and `prayer` IPC alias. Offscreen integration substitutes the layer-shell window boundary and cannot establish actual compositor positioning or focus. Local checks do not establish that a remote CI run has passed.
