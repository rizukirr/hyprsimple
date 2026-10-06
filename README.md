# hyprsimple

Minimal Hyprland dotfiles for Arch Linux. Clean, functional, no bloat.

> [!Note]
> This dotfile have builtin [muslimtify](https://github.com/rizukirr/muslimtify). A prayer time notification daemon for Linux. Run `muslimtify-remove` to uninstall it (package and daemon). Run `muslimtify-add` to re-enable it later. Both commands are idempotent. The bar shows prayer times whenever muslimtify is installed.

> [!Warning]
> Installing from a tag is recommended instead of running directly from the `main` branch. The `main` branch is my active development branch, so it may be unstable and could potentially break your Hyprland configuration.
> Unless you're familiar with Hyprland configuration and don't mind dealing with potential issues, I recommend using a tagged release. But ultimately, it's up to you.

<img width="1920" height="1080" alt="2026-10-04-230902_screenshot" src="https://github.com/user-attachments/assets/d7956807-db97-4db4-8b38-58d3a6fc0630" />

## Demo

https://github.com/user-attachments/assets/f43671d7-4cd2-4cef-a13d-b3c28e432ccd

## Features

- **40 themes** with one-key switching, all apps update at once (the bar with its menus and notifications, ghostty, hyprlock, btop). The well known colorschemes are here, Dracula, Solarized, Catppuccin, Tokyo Night, Rosé Pine, Gruvbox, Nord, Everforest, Kanagawa, Ayu, Nightfox, Oxocarbon and more, dark and light
- **Visual pickers** for themes and wallpapers: a carousel of previews in a panel of the bar, with each theme's colour swatches, filterable by typing
- **Per-theme wallpapers**, one picked for every theme, with picker and cycle support
- **Hardware auto-detection** at install (NVIDIA, hybrid GPU power saving, Vulkan, Intel iGPU, WiFi, battery)
- **Wayland-native** session via uwsm, no X11 dependencies
- **Modular Hyprland config** split into focused files
- **GTK/QT theming** with auto light/dark mode per theme
- **Smart battery** with auto brightness and power profiles
- **Screen recording** with mic, system audio, or silent modes
- **Screenshot** for monitor, window, region, or clipboard
- **Clipboard history** in a panel of the bar, with search, pictures shown as pictures, and removing one entry or all of them
- **Nightlight toggle** for warm screen temperature
- **Audio output switching** with one key
- **An app launcher** in a sidebar that grows from the left edge, searching names, keywords and initials, with the apps you start most listed first
- **A Quickshell bar** with panels for the calendar, system usage, volume, microphone, network, bluetooth and power
- **Prayer times** on the bar via muslimtify, with every setting in its panel
- **Firewall** (UFW) configured out of the box
- **In-place updates** via `hyprsimple-update`, which never overwrites your `~/.config`
- **Migrations** that deliver fixes to machines already installed, once each and idempotently
- **One-command diagnostics** with `hyprsimple-debug` for issue reports

## Install

```bash
git clone https://github.com/rizukirr/hyprsimple.git
cd hyprsimple
./install.sh
```

The install asks for your sudo password once, at the start, and then runs to
the end without stopping. Package operations confirm nothing, so you can start
it and walk away. It comes back to you once, at the very end, to ask whether to
log out.

If you would rather read what pacman is about to do, `./install.sh
--interactive` puts every confirmation back, including the full system upgrade.
It also asks which AUR helper to install when you have neither paru nor yay,
instead of taking paru. The helper comes from a repository when your
distribution ships one, and is built from the AUR otherwise. Whichever helper
you already have is the one used
either way, and `HYPRSIMPLE_AUR_HELPER=yay ./install.sh` settles a machine that
has both.

> [!WARNING]
> These dotfiles have only been tested on a fresh Arch Linux install where Hyprland was selected
> as the desktop during installation. Coming from another desktop environment or compositor
> (KDE, GNOME, etc.) is untested and may require manual cleanup.

If you run into a problem installing hyprsimple, please [open an issue](https://github.com/rizukirr/hyprsimple/issues) — thank you!
Run `hyprsimple-debug` first and attach the link it gives you: it bundles your
hardware, journal warnings, migration state, and the install log
(`~/.local/state/hyprsimple/install.log`) into a single paste that expires in 24
hours. Review it before uploading — it includes your hostname and package list.

## Update

> [!IMPORTANT]
> If you installed hyprsimple before it could update itself, run this **once** to
> get on the update system. Unlike `install.sh`, it does not replace your
> `~/.config`:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/rizukirr/hyprsimple/main/bootstrap.sh | bash
> ```
>
> It installs hyprsimple to `~/.local/share/hyprsimple`, refreshes the helper
> scripts, and applies every fix you missed as a migration. After that,
> `hyprsimple-update` is all you need.

```bash
hyprsimple-update
```

This pulls the latest hyprsimple, refreshes the helper scripts in `~/.local/bin`,
installs any newly required packages, and runs pending migrations.

#### Releases or main

A fresh install follows release tags, so `hyprsimple-update` on its own moves
you from one release to the next and never to an untagged commit.

```bash
hyprsimple-update            # stay on the channel you are already on
hyprsimple-update --stable   # switch to the newest release
hyprsimple-update main       # switch to main, and stay there
hyprsimple-update <branch>   # switch to any branch of origin, for testing
```

The choice sticks. Once you run `hyprsimple-update main`, every later bare
`hyprsimple-update` pulls main until you run `hyprsimple-update --stable`. There
is no config file behind this: the channel is whatever the checkout at
`~/.local/share/hyprsimple` is on, which you can read with `hyprsimple-debug`.

Tracking main gets you fixes the day they merge, at the cost of landing on
commits no release has covered.

**An update never edits your `~/.config` files on its own.** Only a migration
does, and only when a default genuinely has to change. Every migration says what
it touched.

A migration either makes one specific edit, or saves your version aside first.
`hyprsimple-refresh-config <path>` writes `<file>.bak.<timestamp>` and prints the
diff before replacing. A larger change may move your file to
`<file>.pre-split.<timestamp>` and tell you where it went. Nothing is deleted.

Migrations only run once per machine; state lives in
`~/.local/state/hyprsimple/migrations`. A fresh install already ships every fix,
so new users skip the history entirely. If one fails you can skip it and carry
on. To reset a single config to the shipped default at any time:

```bash
hyprsimple-refresh-config hypr/hyprlock.conf
```

Writing a migration is documented in [`migrations/README.md`](migrations/README.md).

Some configs cannot be delivered automatically. `starship.toml` and `yazi/yazi.toml` are TOML, and that format has no include directive to hang a default off.

When an update changes one of those and you have your own version, `hyprsimple-update` says so and prints the command to take the new one. It only mentions a file this update actually changed, so editing something on purpose does not nag you every time.

#### Theme templates

Writing a theme of your own is covered in [THEMING.md](THEMING.md), from `colors.toml` to the files each program reads.

Themes are rendered from the `.tpl` files in `~/.local/share/hyprsimple/.config/hypr/themes/templates`, and the install owns them, so a template change reaches you through `hyprsimple-update` with no migration.

To change one, copy it to `~/.config/hypr/themes/templates.user/` under the same name and edit it there. That directory wins over the install, and a file in it with no shipped counterpart is rendered too, so you can add templates of your own.

Older installs have a copy of the templates at `~/.config/hypr/themes/templates`. That directory is no longer read, and an update removes it once every file in it is one hyprsimple shipped. If you had edited one, the whole directory is left alone and you are told which file it was, so you can move it to `templates.user/`.

## Audio

`SUPER + S` opens the bar's volume panel, with a mute switch, a volume slider and every output device. Click a device to make it the default. The microphone has the same panel behind its bar icon. Noise suppression stays on the microphone you choose.

A bluetooth microphone switches the headset into its call profile while it is in use, which lowers playback quality until recording stops. That is how bluetooth headsets work, not something hyprsimple can avoid.

Connecting a bluetooth headset or speaker moves the sound to it. Switching by
hand with `SUPER + S` still wins while that device stays connected, and the
next one to connect takes over again. Turn it off with

```bash
systemctl --user disable --now hyprsimple-audio-autoswitch.service
```

## Network

`wifi` on its own rescans and lists the networks in range. `wifi "MY NETWORK"`
connects to one: an open network, or one you have joined before, connects
straight away, and a secured one asks for the password.

From a keybind or a script there is nobody to ask, so pass it instead:

```bash
wifi "MY NETWORK" "my password"
```

`wifi --help` lists both forms. It uses NetworkManager if it is running, and
iwd otherwise.

## Keybindings

Press **`SUPER + /`** for interactive viewer with fuzzy search.

### Applications

| Key | Action |
|-----|--------|
| `SUPER + T` | Open terminal (Ghostty) |
| `SUPER + B` | Open browser (Brave) |
| `SUPER + A` | App launcher, a sidebar of the bar |
| `SUPER + F` | File manager (Nautilus) |
| `SUPER + V` | Clipboard history, a panel of the bar |
| `SUPER + M` | Color picker |

### Window Management

| Key | Action |
|-----|--------|
| `SUPER + Q` | Kill active window |
| `SUPER + W` | Toggle floating |
| `SUPER + H / J / K / L` | Move focus left / down / up / right |
| `SUPER + SHIFT + Arrow` | Resize window |
| `SUPER + LMB drag` | Move window |
| `SUPER + RMB drag` | Resize window |

### Workspaces

| Key | Action |
|-----|--------|
| `SUPER + [1-9, 0]` | Switch to workspace 1-10 |
| `SUPER + SHIFT + [1-9, 0]` | Move window to workspace 1-10 |
| `SUPER + SHIFT + S` | Move window to scratchpad |
| `SUPER + CTRL + Arrow` | Move the whole workspace to the monitor in that direction |
| `SUPER + Scroll` | Cycle through workspaces |

### Theming & Wallpaper

| Key | Action |
|-----|--------|
| `SUPER + SHIFT + T` | Switch theme, from a carousel of wallpapers and colour swatches |
| `SUPER + SHIFT + W` | Pick a wallpaper from the current theme, same carousel. Its last tile adds one from a file, and the switch under it cycles through them every 30s |

### Screenshot

| Key | Action |
|-----|--------|
| `Print` | Take a screenshot: drag a region, click a window, or click where there is none for the whole screen |

The screen freezes while you pick, and Escape takes nothing. The picture is saved to `~/Pictures/Screenshots` and copied to the clipboard, both.

### Screen Recording

| Key | Action |
|-----|--------|
| `SUPER + R` | Open the recording menu, a panel of the bar, which starts a recording or stops the one that is running. Recording a window asks which one, from a list |

The menu offers a region, a window or the whole screen, each with microphone
audio, system audio, or none. A window is recorded as the area it covered when
you picked it, so moving it or covering it shows in the recording. While something is recording it offers to stop instead,
so the same key both starts and stops.

Recording uses `wl-screenrec` where it can and `wf-recorder` otherwise, and
NVIDIA machines prefer `wf-recorder`. Only `wf-recorder` is required: it comes
from the official repositories, so recording still works if the `wl-screenrec`
build fails during install.

### Media & Brightness

| Key | Action |
|-----|--------|
| `Volume Up / Down` | Adjust volume |
| `Mute` | Toggle mute |
| `Mic Mute` | Toggle microphone mute |
| `Play / Pause` | Media play/pause |
| `Next / Prev` | Media next/previous track |
| `Brightness Up / Down` | Adjust screen brightness |
| `Kbd Brightness Up / Down` | Adjust keyboard backlight |

### System

| Key | Action |
|-----|--------|
| `SUPER + ESC` | Power menu, a panel of the bar |
| `SUPER + SHIFT + L` | Lock screen |
| `SUPER + X` | Exit Hyprland |
| `CTRL + ESC` | Hide or show the bar |
| `SUPER + N` | Toggle nightlight |
| `SUPER + D` | Dismiss notifications |
| `SUPER + SHIFT + I` | Toggle idle lock |
| `SUPER + S` | Open the volume panel, to set the volume and choose a speaker |
| `SUPER + ALT + S` | Open the microphone panel |
| `SUPER + SHIFT + N` | Open the network panel |
| `SUPER + SHIFT + B` | Open the bluetooth panel |
| `SUPER + SHIFT + D` | Open the notifications panel |
| `SUPER + C` | Open the calendar panel |
| `SUPER + P` | Open the prayer times panel |
| `SUPER + I` | Open the system panel |
| `SUPER + SHIFT + M` | Toggle monitor mirroring |
| `SUPER + CTRL + V` | Toggle virtual mirror |
| `SUPER + /` | Show all keybindings, in a searchable panel of the bar |

## Scripts

Helper scripts live in [`.local/bin`](.local/bin) (installed to `~/.local/bin`, which is on `PATH`).
Most are wired to keybindings or the bar; all can also be run directly from a terminal.

### Audio

| Script | Description |
|--------|-------------|
| `audio-switch.sh` | Cycle through available audio output devices, for a bind of your own |
| `hyprsimple-clipboard-menu.sh` | Opens the bar's clipboard history panel, behind `SUPER + V` |
| `volume-notify.sh` | Show the current PipeWire volume as a notification |
| `record-audio.sh` | Record audio from the default input to `~/Music` |

### Display, Theme & Wallpaper

| Script | Description |
|--------|-------------|
| `brightness-notify.sh` | Show the current screen brightness as a notification |
| `keyboard-brightness.sh` | Control the keyboard backlight (`up` / `down` / `cycle`) |
| `toggle-nightlight.sh` | Toggle a warm screen temperature via hyprsunset |
| `theme-switcher.sh` | Switch theme via the visual picker, or apply one directly by name |
| `theme-apply-templates.sh` | Generate themed app configs from a theme's `colors.toml` |
| `wallpaper-switcher.sh` | Pick, add or cycle a wallpaper within the current theme. `next` cycles, for a bind of your own |
| `hyprsimple-theme-picker.sh` | List one row per theme, with its wallpaper and colour swatches, for the bar's theme picker |
| `hyprsimple-wallpaper-picker.sh` | List one row per wallpaper in the current theme, for the bar's wallpaper picker |
| `hyprsimple-thumbnails.sh` | Swap the image in each of those rows for a small cached thumbnail, which is what the pickers show |
| `live-wallpaper-toggle.sh` | Turn live wallpaper on or off (cycle backgrounds vs. static), behind the switch in the wallpaper picker |
| `monitor-mirror-toggle.sh` | Toggle extend vs. mirror mode for an external monitor |
| `virtual-mirror-toggle.sh` | Mirror a monitor into a window (via wl-mirror) for screen sharing |

### Screenshot & Recording

| Script | Description |
|--------|-------------|
| `screenshot.sh` | Take a screenshot. `smart`, behind `Print`, picks on a frozen screen and both saves and copies. The other modes capture one thing: `region` / `window` / `monitor`, or `region-clipboard` / `window-clipboard` / `clipboard` |
| `screen-record.sh` | Start/stop screen recording (region, window or output; mic, internal, or no audio) |
| `hyprsimple-record-menu.sh` | Opens the bar's record panel, behind `SUPER + R`, which picks what to record and starts or stops it |
| `screen-record-active.sh` | Report whether a screen recording is currently running |

### Network

| Script | Description |
|--------|-------------|
| `hyprsimple-audio-autoswitch.sh` | Move the sound to a bluetooth device when one connects, run as a user service |
| `wifi.sh` | List and connect to WiFi networks, asking for the password when one is needed |
| `hyprsimple-network-setup.sh` | Make NetworkManager run the network, which the bar's network panel needs. A machine on iwd is moved over with its saved networks, and moved back if the network does not return. One already on NetworkManager is left alone |
| `wifi-powersave.sh` | Toggle WiFi power saving (`on` / `off`) |
| `hotspot.sh` | Create a WiFi hotspot with internet sharing |
| `setup-dns.sh` | Configure the DNS provider (Cloudflare / Google / DHCP) |

### System & Power

| Script | Description |
|--------|-------------|
| `battery-monitor.sh` | Low-battery notifications and automatic brightness reduction |
| `bluetooth-toggle.sh` | Toggle Bluetooth adapter power |
| `toggle_cpu_mode.sh` | Switch CPU governor between performance and powersave |
| `hyprsimple-hw-intel-laptop.sh` | Exit 0 on an Intel laptop new enough for thermald (used as a condition) |
| `toggle-idle.sh` | Toggle hypridle (lock-on-idle) on/off |
| `hypr-logout.sh` | Gracefully close all windows and stop the Hyprland session |

### Input & Notifications

| Script | Description |
|--------|-------------|
| `capslock-notify.sh` | Notify on Caps Lock state changes |
| `notification-dismiss.sh` | Dismiss every notification on screen |

### Search & Keybindings

| Script | Description |
|--------|-------------|
| `search.sh` | Fuzzy file finder (ripgrep + fzf) that opens the result in nvim |
| `search_by_keyword.sh` | Fuzzy content search (ripgrep + fzf) that opens the match in nvim |
| `show-keybindings.sh` | Open the bar's keybindings panel, a searchable list of every Hyprland keybinding. `--list` prints them instead |

### hyprsimple management

| Script | Description |
|--------|-------------|
| `hyprsimple-update.sh` | Pull hyprsimple, refresh scripts and packages, run pending migrations. `--stable` or `<branch>` switches channel |
| `hyprsimple-migrate.sh` | Run any migrations that have not run on this machine yet |
| `hyprsimple-refresh-config.sh` | Reset one `~/.config` file to the shipped default, with a backup and a diff |
| `hyprsimple-restart-bar.sh` | Start or restart the bar. `--if-running` restarts a running bar and does nothing otherwise, `--toggle` hides or shows a running bar and starts a stopped one |
| `hyprsimple-debug.sh` | Collect system diagnostics into one file to view, save, or upload |
| `hyprsimple-dev-add-migration.sh` | Create a new migration file (for contributors) |

### Integrations

| Script | Description |
|--------|-------------|
| `hyprsimple-muslimtify.sh` | Add or remove the [muslimtify](https://github.com/rizukirr/muslimtify) prayer-times integration |

### Shell init & internal helpers

These are sourced by other files rather than run directly.

| Script | Description |
|--------|-------------|
| `bashrc.sh` / `zsh.sh` / `fish.fish` | Per-shell init (zoxide, fzf, starship, aliases) sourced from your shell's rc file |
| `terminal.sh` | Detect your login shell and wire the matching init script into its rc file |
| `hypr-helpers.sh` | Shared hyprpaper helper functions used by the wallpaper scripts |
| `hyprsimple-aur-helper.sh` | Reports which AUR helper is installed, so the installer, the updater and muslimtify all use the one you already have |
| `hyprsimple-require.sh` | Loads the helpers a script needs, and stops it rather than letting it run with them missing |
| `hyprsimple-theme-deliver.sh` | Puts a theme's generated files where each program reads them, shared by the theme switcher and the updater |
| `hyprsimple-hw-battery.sh` | Exits 0 when this machine has a battery, which is how hyprsimple decides it is a laptop |
| `hyprsimple-hw-nvidia.sh` | Exits 0 when this machine has an NVIDIA GPU |

## FAQ

Troubleshooting and known issues (NVIDIA boot hang, Plymouth blank-screen splash, and
more) are documented in [FAQ.md](FAQ.md).

## License

MIT
