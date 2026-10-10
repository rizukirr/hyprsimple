# External plugins

A plugin is a Git repository that adds something to the Hyprsimple bar without changing Hyprsimple itself. It can supply any of three things: a widget in the bar, a panel that opens under that widget, and a service that holds state shared by every monitor. `hyprsimple-plugin` installs and manages plugins. They live outside the core checkout and update on their own schedule.

This guide has a part for people who use plugins, a part for people who write them, and a part for people who change the plugin system.

## Using plugins

### Install one

```sh
hyprsimple-plugin owner/repo
hyprsimple-plugin https://github.com/owner/repo.git
```

Both forms do the same thing: download the repository, check its manifest, install the packages it declares, run its enable script and show it in the bar. Only HTTPS GitHub repositories are accepted, and Git never prompts for credentials.

Read a plugin's repository before you install it. A plugin's QML runs inside your bar, its scripts run as your user, and its dependencies can ask for a privileged package install. The manifest check confirms the plugin is well formed. It is not a sandbox.

### Commands

| Command | What it does |
|---|---|
| `hyprsimple-plugin install SOURCE` | Install and enable a plugin. `install` can be left out. |
| `hyprsimple-plugin install --local PATH` | Install from a Git repository on this machine. |
| `hyprsimple-plugin list` | Print each installed plugin's ID, version and whether it is enabled. |
| `hyprsimple-plugin enable ID` | Enable an installed plugin, or retry one whose activation failed. |
| `hyprsimple-plugin disable ID` | Hide the plugin and stop its background work. The code stays installed. |
| `hyprsimple-plugin update ID` | Move the plugin to the newest commit of the repository it came from. |
| `hyprsimple-plugin remove ID` | Disable the plugin and delete its code. |

A running bar restarts once after each command that changes something, so the result is visible straight away.

### Where things live

| Path | Contents |
|---|---|
| `~/.local/share/hyprsimple-plugins/<id>` | The plugin's code, a Git checkout. |
| `~/.config/hyprsimple/plugins.json` | Which plugins are enabled, where each widget sits and each plugin's settings. |
| `~/.local/state/hyprsimple/plugins/manager.lock` | The lock that stops two manager commands running at once. |

`plugins.json` looks like this:

```json
{
  "schemaVersion": 1,
  "plugins": {
    "example": {
      "enabled": true,
      "placement": "left",
      "settings": {}
    }
  }
}
```

You can edit this file. Restart the bar afterwards with `hyprsimple-restart-bar.sh`.

- `placement` moves the widget. `left` puts it after the workspaces, `center` after the clock and `right` before the status items.
- `settings` is passed to the plugin as it is. A plugin's README says which keys it reads, if any.

The manager keeps `placement` and `settings` when a plugin is updated, disabled, removed or installed again.

### Bind a key to a panel

A plugin binds no keys. Keys are yours. A plugin with a panel names one or more aliases for it, and you bind a key to an alias in `~/.config/hypr/bindings/applications.lua`:

```lua
hl.bind("SUPER + P", hl.dsp.exec_cmd(vars.barPanel .. "example"), { description = "Example (panel)" })
```

`vars.barPanel` is the command that toggles a bar panel by name, so the same panel opens from a terminal or a script:

```sh
qs -p ~/.local/share/hyprsimple/default/quickshell ipc call bar toggle example
```

Every panel also answers to `plugin:<id>`, whether or not the plugin declares an alias.

### Updates

`hyprsimple-update` updates Hyprsimple and leaves every plugin on the commit it has. Run `hyprsimple-plugin update <id>` to update a plugin. Review what changed first, for the same reason you review a plugin before installing it.

An update is refused when the installed checkout has local changes. Commit, stash or discard them first.

### When something goes wrong

| Symptom | What happened | What to do |
|---|---|---|
| Install ends with "installed disabled, retry enable" | The enable script failed. The code is installed but the plugin is off. | Fix what the script reported, then run `hyprsimple-plugin enable <id>`. |
| "dependency installation failed" | A declared package could not be installed. Nothing else was changed. | Install the package yourself or fix the package manager, then run the command again. |
| Update ends with "old code and config restored" | The new version failed to activate. The previous version is back in place and running. | Report it to the plugin's author. Your install is as it was. |
| "lifecycle rollback failed" during an update | The previous version was restored but its enable script failed too. | Run `hyprsimple-plugin enable <id>` once the cause is fixed. |
| "disable incomplete" | The plugin is hidden but its disable script failed, so background work may still run. | Run the same command again. |
| The widget is missing after a bar restart | The plugin failed to load. | Run the bar from a terminal and look for a line starting `plugin <id>:`. |
| "invalid plugin config" | `plugins.json` is not valid JSON or has no `plugins` object. | Fix the file by hand. |

A plugin that fails to load never takes the bar down. The bar reports it and carries on with the others.

### The default plugin

A fresh install enables [`muslimtify-org/muslimtify-hyprsimple`](https://github.com/muslimtify-org/muslimtify-hyprsimple), which shows prayer times, and installs the `muslimtify` package it depends on. Its widget sits on the left and its panel alias is `prayer`. No key is bound to it. `~/.config/hypr/bindings/applications.lua` carries a commented `SUPER + P` line to enable.

```sh
hyprsimple-plugin remove muslimtify
hyprsimple-plugin muslimtify-org/muslimtify-hyprsimple
```

Removing it keeps your Muslimtify settings and the installed package.

## Writing a plugin

### A complete plugin in five files

This plugin puts a button in the bar that opens a small panel. Create a directory with these files.

`manifest.json`:

```json
{
  "schemaVersion": 1,
  "apiVersion": 1,
  "id": "example",
  "name": "Example plugin",
  "version": "1.0.0",
  "entryPoints": {"widget": "Widget.qml", "panel": "Panel.qml"},
  "lifecycle": {"enable": "enable.sh", "disable": "disable.sh"},
  "panelAliases": ["example"]
}
```

`Widget.qml`:

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

`Panel.qml`:

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

`enable.sh` and `disable.sh`, for a plugin with no background work:

```bash
#!/bin/bash
set -euo pipefail
exit 0
```

A plugin with nothing to start or stop can leave `lifecycle` out of the manifest and skip both scripts.

Commit the files, then install from the directory:

```sh
git init -b main
git add .
git commit -m "Add example plugin"
hyprsimple-plugin install --local "$PWD"
hyprsimple-plugin list
```

### The development loop

A local install clones what is committed. It does not link to your working directory, so an uncommitted edit is not installed. To try a change:

```sh
git commit -am "Try a change"
hyprsimple-plugin update example
```

`update` on a local install reads the directory it was installed from. It runs the same steps a user's update runs, including the disable and enable scripts, so this loop also tests your lifecycle.

To see why a plugin did not load, stop the bar and run it in a terminal:

```sh
QML_IMPORT_PATH="$HOME/.local/share/hyprsimple/default/quickshell" qs -p ~/.local/share/hyprsimple/default/quickshell
```

Load failures print as `plugin <id>: <reason>`. Set `HYPRSIMPLE_PLUGIN_ROOT` to keep development plugins in a directory of their own, apart from the ones you use.

### Manifest reference

`manifest.json` sits at the root of the repository.

| Field | Required | Value |
|---|---|---|
| `schemaVersion` | Yes | The integer `1`. |
| `apiVersion` | Yes | The integer `1`. The plugin API this plugin was written for. |
| `id` | Yes | Lowercase letters and digits in segments joined by `.` or `-`, starting with a letter. It names the install directory, the config entry and the panel. IDs starting `hyprsimple.` are reserved. |
| `name` | Yes | A display name. |
| `version` | Yes | Any non-empty string. Shown by `list`. |
| `entryPoints` | Yes | An object with at least one of `service`, `widget` and `panel`, each a path to a `.qml` file. |
| `placement` | No | `left`, `center` or `right`. Where the widget goes when the user has not chosen. Defaults to `left`. |
| `dependencies` | No | An object with `packages` and `aur`, each an array of package names. |
| `lifecycle` | No | An object with `enable` and `disable`, each a path to a Bash script. |
| `panelAliases` | No | An array of names for the panel, lowercase letters, digits and hyphens. Needs a `panel` entry point. |

Paths are relative to the repository root, contain no `.` or `..` segments, and must name files that exist. Any field not in this table is rejected, so a typo in a field name fails the install instead of being ignored. An ID or alias already used by another installed plugin is rejected too.

The manager checks the manifest when a plugin is installed, enabled or updated. The bar does not check it again.

### Entry points

Every entry point declares `required property var context`. Without it the entry point is not loaded.

A service is created once, when the bar starts, and lives as long as the bar does. Put anything here that should exist once however many monitors there are: a process that polls, a file watcher, state that every widget shows. It has no screen and no bar.

A widget is created once per monitor, in that monitor's bar. Wrap it in `Capsule` to match the built-in bar items. A widget that sets `visible: false` takes no space, which suits something that has nothing to show yet.

A panel is created once per monitor, next to the widget. Build it on `PopupPanel` so it opens under the widget, closes on an outside click or Escape, and takes part in the rule that one panel is open at a time across all monitors.

When a service is declared and fails to load, the plugin's widget and panel are not loaded either, since they would have nothing to read.

### The context object

| Member | Type | In a service | In a widget or panel |
|---|---|---|---|
| `pluginId` | string | The plugin's ID. | The same. |
| `settings` | object | The plugin's `settings` from `plugins.json`. | The same. |
| `theme` | object | The `Theme` singleton. | The same. |
| `service` | object | The service itself. | The shared service, or `null` when none is declared. |
| `screen` | object | `null`. | The monitor this instance is on. |
| `bar` | object | `null`. | The bar this instance is in. |
| `anchorItem` | Item | `null`. | The widget's slot in the bar, which a panel opens under. |
| `panelId` | string | `plugin:<id>`. | The same. |
| `panelOpen` | bool | `false`. | Whether this monitor's bar has this plugin's panel open. |
| `togglePanel()` | function | Does nothing. | Opens or closes the panel on this monitor. |
| `closePanel()` | function | Does nothing. | Closes the panel if it is open here. |

Each monitor gets its own context, and all of them point at the same service.

### The shared module

`import Hyprsimple` gives a plugin the same building blocks the built-in bar uses. They resolve to the core's own files, so a plugin follows the user's theme and picks up core changes without copying anything.

| Kind | Types |
|---|---|
| Theme | `Theme` |
| Bar | `Capsule`, `StatusButton` |
| Panel | `PopupPanel` |
| Text and icons | `StyledText`, `SectionLabel`, `Icon` |
| Controls | `TextButton`, `IconButton`, `Toggle`, `Slider`, `Segmented`, `Dropdown`, `TextField` |
| Lists | `ListRow`, `PickerList` |
| Feedback | `Meter`, `Spinner`, `StateLayer` |
| Animation | `Anim`, `CAnim`, `Spring` |

`StatusButton` has `icon`, `label`, `tooltip`, `active`, `highlighted`, `alert`, `dim` and a `clicked` signal.

`PopupPanel` needs `bar`, `anchorItem` and `name`, set from the context as in the example. It also has `panelWidth`, a read-only `open`, `focusTarget` for the item that takes the keyboard when the panel opens, and `dismiss()`.

`Theme` holds every color and size. Use its tokens instead of literal values so the plugin follows theme changes while the bar runs.

| Group | Tokens |
|---|---|
| Colors | `bg`, `surface`, `fg`, `muted`, `accent`, `secondary`, `onAccent`, `danger` |
| Spacing | `xs`, `sm`, `md`, `lg` |
| Type | `font`, `iconFont`, `fontSize`, `fontSizeSmall`, `fontSizeLarge`, `iconSize` |
| Panels | `panelWidth`, `panelWidthNarrow`, `panelWidthWide`, `radius` |

`default/quickshell/theme/Theme.qml` has the full list. A plugin can also import Quickshell modules and its own files, such as `import "lib/Model.js" as Model`.

### Lifecycle scripts

`lifecycle.enable` runs when the plugin is installed or enabled and after an update. `lifecycle.disable` runs when it is disabled or removed and before an update. Both run with Bash from the plugin's directory, with `HYPRSIMPLE_PLUGIN_ID` set.

Use them for work that outlives the bar: registering a user service, starting a daemon, creating a file another program needs. A plugin that only draws needs neither.

Three rules keep them reliable.

1. Return zero only when the work is done. Check the result before exiting, because the manager records the plugin as enabled on the strength of that exit status.
2. Be safe to run twice. A failed enable is retried from the top, and a disable can run against a plugin that was only half enabled.
3. Leave the user's data alone on disable. Removal is expected to keep the application's settings and the installed packages.

When enable fails, the manager runs disable to clean up and leaves the plugin installed and disabled.

### Dependencies

`dependencies.packages` are official repository packages, installed with `pacman`. `dependencies.aur` are AUR packages, installed with the AUR helper Hyprsimple already uses. Only missing packages are installed, and each is checked again afterwards. If one cannot be installed, the install stops before any plugin code is put in place.

Packages are never uninstalled, on disable or on removal.

### Settings

Whatever object the user puts under `settings` for the plugin in `plugins.json` arrives as `context.settings`. There is no schema and no manager command to set a value: the user edits the file and restarts the bar. Read each key with a fallback, as `context.settings.label ?? "Example"` does, and document the keys in the plugin's README.

A plugin that fronts an application with its own configuration file can read and write that file from its service and leave `settings` empty. The Muslimtify plugin does this.

### Make the plugin callable from a key

A plugin cannot bind a key, because keys belong to the user. What it does is expose a name that the user's keybinding calls. There are two ways to expose one.

#### Open the panel

This is the common case and needs no code beyond the manifest. Three things have to be true.

1. The manifest declares a `panel` entry point.
2. The panel is a `PopupPanel` with `name: context.panelId`, as in the example. That name is how the bar finds it.
3. The manifest declares at least one alias in `panelAliases`. Without one the panel is still reachable as `plugin:<id>`, which is awkward to type.

```json
"entryPoints": {"widget": "Widget.qml", "panel": "Panel.qml"},
"panelAliases": ["example"]
```

Test it from a terminal with the plugin installed and the bar running. The panel should open on the focused monitor, and the same command should close it:

```sh
qs -p ~/.local/share/hyprsimple/default/quickshell ipc call bar toggle example
```

Then give users the line to add to `~/.config/hypr/bindings/applications.lua` in your README. `vars.barPanel` is that same command up to the panel name:

```lua
hl.bind("SUPER + P", hl.dsp.exec_cmd(vars.barPanel .. "example"), { description = "Example (panel)" })
```

Suggest a key, and leave the choice to the user. Aliases are shared by all installed plugins and by the built-in panels, so pick one specific to your plugin. An alias another installed plugin already uses fails the install.

#### Run an action of your own

For anything other than toggling the panel, such as refreshing data or switching a mode, declare an `IpcHandler` in the service. Put it in the service and not in the widget or panel: those exist once per monitor, and a handler's target must be unique.

```qml
import QtQuick
import Quickshell.Io

Item {
    id: root
    required property var context

    function refresh() { /* reload the data */ }

    IpcHandler {
        target: "example"
        function refresh(): void { root.refresh() }
    }
}
```

Use the plugin's ID as the `target`, so it cannot collide with another plugin's or with the bar's own `bar` target. Every function needs type annotations on its arguments and return value, or Quickshell does not expose it.

Test it, and list what the running bar exposes:

```sh
qs -p ~/.local/share/hyprsimple/default/quickshell ipc call example refresh
qs -p ~/.local/share/hyprsimple/default/quickshell ipc show
```

The line for users is built from `vars.bar`, the bar's directory:

```lua
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("qs -p " .. vars.bar .. " ipc call example refresh"), { description = "Example: refresh" })
```

Document each function in the README. They are part of what users bind to, so renaming one breaks their keybindings.

### Worked example: the Muslimtify plugin

[`muslimtify-org/muslimtify-hyprsimple`](https://github.com/muslimtify-org/muslimtify-hyprsimple) is the plugin Hyprsimple installs by default, and it uses every part of the API. It puts the next prayer time in the bar and opens a panel with today's times and the settings. Read this section beside that repository when you write a plugin that fronts a command-line program.

Muslimtify itself is a separate program with a `muslimtify` command, a background daemon that sends the notifications and a config file. The plugin draws what the command reports and calls the command to change settings. It never computes a prayer time or writes the config file itself.

#### Layout

```
manifest.json
Service.qml            the only file that runs muslimtify or reads its config
Widget.qml             the bar item
Panel.qml              the panel, which switches between two views
views/TodayView.qml
views/SettingsView.qml
components/            small pieces the views share
lib/Model.js           pure functions: parsing, countdowns, argument lists
scripts/enable.sh
scripts/disable.sh
assets/
test/
```

Only the three entry points and the two scripts are named in the manifest. Everything else is the plugin's own business, reached through relative imports such as `import "views"` and `import "lib/Model.js" as Model`.

#### Manifest

```json
{
  "schemaVersion": 1,
  "apiVersion": 1,
  "id": "muslimtify",
  "name": "Muslimtify",
  "version": "1.0.0",
  "entryPoints": {
    "service": "Service.qml",
    "widget": "Widget.qml",
    "panel": "Panel.qml"
  },
  "placement": "left",
  "dependencies": {"aur": ["muslimtify"]},
  "lifecycle": {
    "enable": "scripts/enable.sh",
    "disable": "scripts/disable.sh"
  },
  "panelAliases": ["prayer"]
}
```

Each field is there for a reason.

- `dependencies.aur` makes `hyprsimple-plugin` install the `muslimtify` package before any plugin code is put in place, so the scripts and the service can rely on the command existing.
- `lifecycle` registers and unregisters the daemon. The bar only displays prayer times. The daemon is what notifies, and it has to run whether or not the bar does.
- `service` is declared because the schedule is the same on every monitor. One service fetches it, and each monitor's widget and panel read it.
- `panelAliases` gives the panel the name `prayer`, which is what users bind a key to.

#### Lifecycle scripts

`scripts/enable.sh`:

```bash
#!/bin/bash
set -euo pipefail
muslimtify daemon install
muslimtify daemon status
```

The second command is the check. `daemon install` returning zero is not taken as proof, so the script asks for the status and fails if the daemon is not up. A failure leaves the plugin installed and disabled, and `hyprsimple-plugin enable muslimtify` runs the script again. Both commands are safe to repeat.

`scripts/disable.sh`:

```bash
#!/bin/bash
set -euo pipefail
# Unregister the daemon without removing application settings or packages.
if command -v muslimtify >/dev/null 2>&1; then
  muslimtify daemon uninstall
fi
```

It tests for the command first, so disabling still succeeds on a machine where the package was removed by hand. It leaves `~/.config/muslimtify/config.json` alone.

#### Service

`Service.qml` is the single place that talks to Muslimtify. Shortened, its shape is this:

```qml
import QtQuick
import Quickshell
import Quickshell.Io
import "lib/Model.js" as Model

Item {
    id: root
    required property var context

    property bool available: false
    property var config: Model.defaultConfig()
    property var today: null
    property var tomorrow: null
    readonly property var next: Model.nextPrayer(root.today, root.tomorrow, root.nowMinutes)

    function refresh() { todayProcess.running = true; tomorrowProcess.running = true }
    function setMethod(name) { root.run("calculation.method", Model.methodArgs(name)) }

    // Is muslimtify installed? env exits 127 when it is not on PATH.
    Process {
        command: ["env", "muslimtify", "version"]
        running: true
        onExited: exitCode => { root.available = exitCode === 0; if (root.available) root.refresh() }
    }

    // The config file is the source of truth. Reload and refresh when it changes.
    FileView {
        path: root.configPath
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.applyConfig(text())
    }

    Process { id: todayProcess; command: ["muslimtify"].concat(Model.scheduleArgs(0)) }
    Process { id: tomorrowProcess; command: ["muslimtify"].concat(Model.scheduleArgs(1)) }
}
```

Four choices here are worth copying.

1. It probes for the command once at startup and exposes `available`. The widget and views show a clear state when the program is missing instead of failing.
2. Reads and writes both go through the program. A setter such as `setMethod` queues a `muslimtify` command. When the command finishes, the service reloads the config file, and the views follow the file. Nothing in the UI changes a value before the program has saved it, so the bar cannot show a setting the program rejected.
3. Commands are passed as argument arrays, never as a shell string, so a value typed into a settings field cannot become shell syntax.
4. The logic is in `lib/Model.js` as pure functions. `test/model-test.js` tests them with Node.js alone, with no bar running.

#### Widget

`Widget.qml` in full:

```qml
import QtQuick
import Hyprsimple
import "lib/Model.js" as Model

// Left click opens the panel. Right click switches to the countdown.
Capsule {
    id: root
    required property var context
    readonly property var service: context.service
    property bool showRemaining: false
    readonly property bool active: context.panelOpen
    readonly property string label: service.next ? Model.barLabel(service.next, showRemaining) : ""
    readonly property bool soon: !!service.next && service.next.remaining <= Model.SOON_MINUTES
    visible: !!service.next

    StatusButton {
        label: root.label
        active: root.active
        highlighted: root.soon
        tooltip: root.service.next ? `${Model.title(root.service.next.name)} at ${root.service.next.time}, in ${Model.formatDuration(root.service.next.remaining)}` : ""
        onClicked: root.context.togglePanel()
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: root.showRemaining = !root.showRemaining
        }
    }
}
```

It holds no data of its own. It reads `context.service.next`, hides itself with `visible` until there is a next prayer, and calls `context.togglePanel()` on click. `showRemaining` is per monitor because it is a property of the widget, not of the service.

#### Panel

`Panel.qml` sets the three properties every plugin panel sets, then loads one of two views:

```qml
PopupPanel {
    id: root
    required property var context
    readonly property var service: context.service
    bar: context.bar
    anchorItem: context.anchorItem
    name: context.panelId
    property bool settingsOpen: false

    panelWidth: settingsOpen ? Theme.panelWidthWide : Theme.panelWidth
    focusTarget: keys
    onOpenChanged: if (!open) settingsOpen = false

    Item {
        id: keys
        Keys.onPressed: event => {
            const key = event.text.toLowerCase()
            if (event.key === Qt.Key_Escape && root.settingsOpen) root.setSettingsOpen(false)
            else if (key === "s") root.setSettingsOpen(!root.settingsOpen)
            else if (key === "r") root.service.refresh()
            else return
            event.accepted = true
        }
        Loader { sourceComponent: root.settingsOpen ? settingsPage : todayPage }
    }
}
```

`focusTarget` names the item that receives keys when the panel opens. A key the handler does not accept carries on to `PopupPanel`, which closes on Escape. That is why Escape first leaves settings and then closes the panel.

#### Settings and the key

The plugin leaves its `settings` object in `plugins.json` empty. Location, calculation method and reminders already have a home in Muslimtify's own config file, and keeping a second copy in Hyprsimple would let the two disagree.

It binds no key. Its README gives users this line for `~/.config/hypr/bindings/applications.lua`:

```lua
hl.bind("SUPER + P", hl.dsp.exec_cmd(vars.barPanel .. "prayer"), { description = "Prayer Times (panel)" })
```

#### Tests

`bash test/check.sh` runs three things without Hyprsimple: the model tests, a lifecycle test that runs both scripts against a stubbed `muslimtify` and checks that failures propagate, and a check that the manifest's files exist. With `HYPRSIMPLE_SOURCE` pointing at a Hyprsimple checkout it also installs the plugin with the real manager into an isolated home and loads the real service, widget and panel in Quickshell offscreen.

#### Building a plugin like it

To front another command-line program the same way:

1. List the program's package under `dependencies`.
2. If it has a daemon or a user service, start it in `enable.sh` and check that it started. Stop it in `disable.sh`.
3. Write one service that runs the program and exposes what it reports as properties. Probe for the program first.
4. Keep parsing and formatting in a plain JavaScript file you can test without the bar.
5. Write a widget that reads the service and hides itself when there is nothing to show.
6. Write a panel on `PopupPanel`, and send every change through the service.
7. Declare a panel alias and put the keybinding line in your README.

### Before publishing

- Install from a clean clone with `hyprsimple-plugin install --local`, then run `disable`, `enable`, `update` and `remove`.
- Make the enable script fail on purpose and confirm that `enable` works once it is fixed.
- Open the panel on each monitor if you have more than one.
- Switch themes with the bar running and confirm the colors follow.
- Document the panel alias, the settings keys and what the lifecycle scripts start.

Users then install with `hyprsimple-plugin owner/repo`. Keep `apiVersion` at `1` until Hyprsimple documents another.

## How it works

### What each command does

Every command takes one lock first, so two commands never touch the same plugin at once.

`install` clones the repository into a staging directory beside the plugin root, checks the manifest, checks that the ID and aliases are free, installs dependencies, moves the code into place, runs the enable script, records the plugin as enabled and restarts the bar. Nothing is put in place if the manifest or a dependency fails. If the enable script fails, the code stays and the plugin is recorded as disabled.

`enable` does nothing when the plugin is already enabled. Otherwise it checks the manifest, installs dependencies, runs the enable script, records the plugin as enabled and restarts the bar.

`disable` records the plugin as disabled and restarts the bar before it runs the disable script, so the widget is gone even if the script fails. `remove` does the same and then deletes the code. The plugin's entry in `plugins.json` stays, disabled, so its placement and settings survive a reinstall.

`update` refuses a checkout with local changes. It clones the plugin's origin, checks the new manifest and installs new dependencies. Then it disables the old version, swaps the code, enables the new version and restarts the bar. If any step after the swap begins fails, it puts the old code and the old `plugins.json` back and enables the old version again.

### How the bar loads plugins

When the bar starts, `default/quickshell/plugins/Registry.qml` reads `plugins.json` and every installed `manifest.json` with one shell process that uses builtins only. For each plugin marked enabled it creates the service, if there is one. Each monitor's bar then has three `PluginSlot` rows, one per placement, which create the widget and panel for the plugins placed there.

The bar does not validate manifests. The manager is the only validator, and the bar loads what `plugins.json` marks enabled. A plugin copied into the plugin directory by hand has no entry there and is not loaded.

A file that is not valid JSON, an enabled plugin whose directory is missing and QML that fails to compile are each reported under the plugin's ID and skipped. The rest of the bar loads.

The bar's `toggle` IPC call resolves an alias to `plugin:<id>` before it toggles, which is why aliases and built-in panel names work the same way from a keybinding.

### Delivery to existing installs

Migration `migrations/1791551522.sh` moves an existing install to the external Muslimtify plugin. It first copies the manager into `~/.local/bin`, because the first update may still be running an updater that only delivers `.sh` and `.fish` files. Then it installs and enables the plugin where Muslimtify is present. It keeps `~/.config/muslimtify/config.json`, the plugin's settings and placement, and the user's Hyprland bindings. A plugin the user had deliberately disabled stays disabled, and an install without Muslimtify downloads nothing. A failed activation leaves a pending marker and no completion marker, so the next update tries again.

Migration `migrations/1791554376.sh` removes the old `hyprsimple-muslimtify.sh` helper.

### Tests

| Suite | Covers |
|---|---|
| `test/plugin-manager-test.sh` | Every manager command against local fixture repositories, with an isolated HOME and stubbed package and desktop commands. |
| `test/plugin-loader-test.sh` | The real loader in Quickshell offscreen: imports, the shared service, per-monitor contexts, theme changes, panel toggling and failure containment. Needs Quickshell. |
| `test/plugin-default-install-test.sh` | The installer's default plugin step and its failure messages. |
| `test/plugin-migration-test.sh` | The migration, including the disabled and absent cases. |
| `test/plugin-update-delivery-test.sh` | A real update from the pre-plugin updater at `9c9ba72` through the migration, then an independent plugin update and a failed one. |

The last three use the published Muslimtify plugin as a fixture, pinned to commit `2f2b9028b3833e6cb4dc25b5b138fc18ef74bfea`. They never use the network. CI fetches that commit once. Locally, point the suites at a checkout of it:

```sh
export MUSLIMTIFY_PLUGIN_FIXTURE=/path/to/muslimtify-hyprsimple
bash test/plugin-default-install-test.sh
bash test/plugin-migration-test.sh
bash test/plugin-update-delivery-test.sh
```

The plugin repository has checks of its own, which load its real service, widget and panel against a core checkout:

```sh
cd /path/to/muslimtify-hyprsimple
HYPRSIMPLE_SOURCE=/path/to/hyprsimple bash test/check.sh
```

Offscreen tests cannot create a layer-shell window. Panel placement on each monitor, keyboard focus, outside-click dismissal and Escape need checking in a real Hyprland session.
