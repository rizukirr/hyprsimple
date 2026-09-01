# hyprsimple

Minimal Hyprland dotfiles for Arch Linux. Clean, functional, no bloat.

> [!Note]
> This dotfile have builtin [muslimtify](https://github.com/rizukirr/muslimtify). A prayer time notification daemon for Linux. Run `muslimtify-remove` to uninstall it (package, daemon, waybar module, and CSS). Run `muslimtify-add` to re-enable it later. Both commands are idempotent and back up your waybar config to `.bak` before editing.

> [!Warning]
> Installing from a tag is recommended instead of running directly from the `main` branch. The `main` branch is my active development branch, so it may be unstable and could potentially break your Hyprland configuration.
> Unless you're familiar with Hyprland configuration and don't mind dealing with potential issues, I recommend using a tagged release. But ultimately, it's up to you.


<img width="1920" height="1080" alt="image1" src="https://github.com/user-attachments/assets/c10495c5-dda8-44a1-be69-8f6ac0f965b4" /> 

| Power Menu | Terminal|
|----------------------------------|--------------------------------|
| <img width="1920" height="1080" alt="2026-08-31-231634_hyprshot" src="https://github.com/user-attachments/assets/c2e9b0b1-5f92-4bc1-984f-8b14542a74dc" /> | <img width="1920" height="1080" alt="2026-08-31-231849_hyprshot" src="https://github.com/user-attachments/assets/5609d417-fa72-4387-bec9-d898f4513bab" /> |

| Menu Launcher | Theme Switcher |
|-------------------------------------|-------------------------------------|
| <img width="1920" height="1080" alt="2026-08-31-231603_hyprshot" src="https://github.com/user-attachments/assets/8d0913ea-b47f-4f62-9c1b-eb7d31bcab83" /> | <img width="1920" height="1080" alt="2026-08-30-235001_hyprshot" src="https://github.com/user-attachments/assets/a32760b2-e947-4a88-86e3-296142599933" /> |

## Features

- **16 themes** with one-key switching, all apps update at once (waybar, rofi, ghostty, hyprlock, dunst, btop)
- **Visual pickers** for themes and wallpapers: a rofi grid of previews with each theme's colour swatches, filterable by typing
- **Per-theme wallpapers** with picker and cycle support
- **Per-theme backgrounds** for app launcher and power menu
- **Hardware auto-detection** at install (NVIDIA, Vulkan, Intel iGPU, WiFi, battery)
- **Wayland-native** session via uwsm, no X11 dependencies
- **Modular Hyprland config** split into focused files
- **GTK/QT theming** with auto light/dark mode per theme
- **Smart battery** with auto brightness and power profiles
- **Screen recording** with mic, system audio, or silent modes
- **Screenshot** for monitor, window, region, or clipboard
- **Clipboard history** via cliphist + rofi
- **Nightlight toggle** for warm screen temperature
- **Audio output switching** with one key
- **Prayer times** on waybar via muslimtify
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

Some configs cannot be delivered automatically. `starship.toml`, `yazi/yazi.toml` and `hypr/hyprsunset.conf` are TOML, and `wlogout/layout` is a stream of JSON objects, so none of them has an include directive to hang a default off the way rofi and dunst do.

When an update changes one of those and you have your own version, `hyprsimple-update` says so and prints the command to take the new one. It only mentions a file this update actually changed, so editing something on purpose does not nag you every time.

#### Rofi

Rofi's defaults live in the install, at `~/.config/rofi/hyprsimple`, which is a
link into `~/.local/share/hyprsimple`. What sits in `~/.config/rofi` is a short
file per config that imports its default:

```
@import "hyprsimple/config.rasi"
```

Put your own settings **below** that line. Rofi applies the later declaration,
so anything you set there wins property by property, and anything you leave out
keeps hyprsimple's value and keeps receiving updates to it. A setting placed
above the import is silently overridden by the default, with no error.

Because the defaults are a link rather than a copy, a rofi change reaches you
through `hyprsimple-update` alone. No migration is involved.

If the split migration reported that one of your files was left alone, it had
edits of its own and is not importing anything. To take the stub and keep a
backup of yours:

```bash
hyprsimple-refresh-config rofi/config.rasi
```

`rofi/launcher` and `rofi/powermenu` are not part of this. Both are links into
the active theme and their styles are rewritten on every theme switch, so they
belong to the theme rather than to you.

#### Theme templates

Themes are rendered from the `.tpl` files in `~/.local/share/hyprsimple/.config/hypr/themes/templates`, and the install owns them, so a template change reaches you through `hyprsimple-update` with no migration.

To change one, copy it to `~/.config/hypr/themes/templates.user/` under the same name and edit it there. That directory wins over the install, and a file in it with no shipped counterpart is rendered too, so you can add templates of your own.

Older installs have a copy of the templates at `~/.config/hypr/themes/templates`. That directory is no longer read, and an update removes it once every file in it is one hyprsimple shipped. If you had edited one, the whole directory is left alone and you are told which file it was, so you can move it to `templates.user/`.

## Network

To see the available network interfaces, run `wifi`. To connect to a network, run `wifi <network name>` for example `wifi "MY NETWORK"`

## Keybindings

Press **`SUPER + /`** for interactive viewer with fuzzy search.

### Applications

| Key | Action |
|-----|--------|
| `SUPER + T` | Open terminal (Ghostty) |
| `SUPER + B` | Open browser (Brave) |
| `SUPER + A` | App launcher (Rofi) |
| `SUPER + F` | File manager (Nautilus) |
| `SUPER + O` | Notes (Obsidian) |
| `SUPER + S` | Android Studio |
| `SUPER + E` | Emoji picker |
| `SUPER + V` | Clipboard history |
| `SUPER + M` | Color picker |

### Window Management

| Key | Action |
|-----|--------|
| `SUPER + Q` | Kill active window |
| `SUPER + W` | Toggle floating |
| `SUPER + SHIFT + J` | Toggle split (dwindle) |
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
| `SUPER + Scroll` | Cycle through workspaces |

### Theming & Wallpaper

| Key | Action |
|-----|--------|
| `SUPER + SHIFT + T` | Switch theme, from a grid of wallpapers and colour swatches |
| `SUPER + SHIFT + W` | Pick a wallpaper from the current theme, same grid |
| `SUPER + ALT + W` | Cycle to next wallpaper |
| `SUPER + CTRL + W` | Toggle live wallpaper, cycling backgrounds every 30s |

### Screenshot

| Key | Action |
|-----|--------|
| `Print` | Screenshot current monitor |
| `SUPER + Print` | Screenshot active window |
| `SUPER + ALT + Print` | Screenshot selected region |
| `SUPER + CTRL + Print` | Screenshot region to clipboard |

### Screen Recording

| Key | Action |
|-----|--------|
| `SUPER + R` | Record region with mic audio |
| `SUPER + SHIFT + R` | Record fullscreen with mic audio |
| `SUPER + ALT + R` | Record region with system audio |
| `SUPER + SHIFT + ALT + R` | Record fullscreen with system audio |
| `SUPER + CTRL + R` | Record region without audio |
| `SUPER + CTRL + SHIFT + R` | Record fullscreen without audio |

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
| `SUPER + ESC` | Power menu |
| `SUPER + SHIFT + L` | Lock screen |
| `SUPER + X` | Exit Hyprland |
| `CTRL + ESC` | Toggle waybar |
| `SUPER + N` | Toggle nightlight |
| `SUPER + D` | Dismiss notifications |
| `SUPER + SHIFT + I` | Toggle idle lock |
| `SUPER + F10` | Switch audio output |
| `SUPER + SHIFT + M` | Toggle monitor mirroring |
| `SUPER + CTRL + V` | Toggle virtual mirror |
| `SUPER + /` | Show all keybindings |

## Scripts

Helper scripts live in [`.local/bin`](.local/bin) (installed to `~/.local/bin`, which is on `PATH`).
Most are wired to keybindings or waybar; all can also be run directly from a terminal.

### Audio

| Script | Description |
|--------|-------------|
| `audio-switch.sh` | Cycle through available audio output devices |
| `volume-notify.sh` | Show the current PipeWire volume via a dunst notification |
| `record-audio.sh` | Record audio from the default input to `~/Music` |

### Display, Theme & Wallpaper

| Script | Description |
|--------|-------------|
| `brightness-notify.sh` | Show the current screen brightness via a dunst notification |
| `keyboard-brightness.sh` | Control the keyboard backlight (`up` / `down` / `cycle`) |
| `toggle-nightlight.sh` | Toggle a warm screen temperature via hyprsunset |
| `theme-switcher.sh` | Switch theme via the visual picker, or apply one directly by name |
| `theme-apply-templates.sh` | Generate themed app configs from a theme's `colors.toml` |
| `wallpaper-switcher.sh` | Switch or cycle wallpaper within the current theme |
| `hyprsimple-image-picker.sh` | Render a list of images as a rofi grid and print the key of the one chosen |
| `hyprsimple-theme-picker.sh` | Feed the image picker one tile per theme, with its wallpaper and colour swatches |
| `hyprsimple-wallpaper-picker.sh` | Feed the image picker one tile per wallpaper in the current theme |
| `live-wallpaper-toggle.sh` | Toggle live wallpaper (cycle backgrounds vs. static) |
| `monitor-mirror-toggle.sh` | Toggle extend vs. mirror mode for an external monitor |
| `virtual-mirror-toggle.sh` | Mirror a monitor into a window (via wl-mirror) for screen sharing |

### Screenshot & Recording

| Script | Description |
|--------|-------------|
| `screenshot.sh` | Take a screenshot (`clipboard` / `window` / `region` / `monitor`) |
| `screen-record.sh` | Start/stop screen recording (region or output; mic, internal, or no audio) |
| `screen-record-active.sh` | Report whether a screen recording is currently running |

### Network

| Script | Description |
|--------|-------------|
| `wifi.sh` | List and connect to WiFi networks |
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
| `notification-dismiss.sh` | Dismiss all dunst notifications |

### Search & Keybindings

| Script | Description |
|--------|-------------|
| `search.sh` | Fuzzy file finder (ripgrep + fzf) that opens the result in nvim |
| `search_by_keyword.sh` | Fuzzy content search (ripgrep + fzf) that opens the match in nvim |
| `show-keybindings.sh` | Show all Hyprland keybindings in a rofi fuzzy-search menu |

### hyprsimple management

| Script | Description |
|--------|-------------|
| `hyprsimple-update.sh` | Pull hyprsimple, refresh scripts and packages, run pending migrations. `--stable` or `<branch>` switches channel |
| `hyprsimple-migrate.sh` | Run any migrations that have not run on this machine yet |
| `hyprsimple-refresh-config.sh` | Reset one `~/.config` file to the shipped default, with a backup and a diff |
| `hyprsimple-refresh-waybar.sh` | Reset waybar's config and style, keeping your bar position |
| `hyprsimple-restart-waybar.sh` | Restart waybar. `--if-running` reloads a running bar and does nothing otherwise |
| `hyprsimple-restart-dunst.sh` | Restart dunst, same shape as the waybar one |
| `hyprsimple-debug.sh` | Collect system diagnostics into one file to view, save, or upload |
| `hyprsimple-dev-add-migration.sh` | Create a new migration file (for contributors) |

### Integrations

| Script | Description |
|--------|-------------|
| `hyprsimple-muslimtify.sh` | Add or remove the [muslimtify](https://github.com/rizukirr/muslimtify) prayer-times integration |
| `waybar-muslimtify.sh` | Provide the waybar module output (next prayer + tooltip) for muslimtify |
| `waybar-screenrecording.sh` | Provide the waybar recording indicator. Redrawn on `SIGRTMIN+8`, which `screen-record.sh` sends |

### Shell init & internal helpers

These are sourced by other files rather than run directly.

| Script | Description |
|--------|-------------|
| `bashrc.sh` / `zsh.sh` / `fish.fish` | Per-shell init (zoxide, fzf, starship, aliases) sourced from your shell's rc file |
| `terminal.sh` | Detect your login shell and wire the matching init script into its rc file |
| `hypr-helpers.sh` | Shared hyprpaper helper functions used by the wallpaper scripts |

## FAQ

Troubleshooting and known issues (NVIDIA boot hang, Plymouth blank-screen splash, and
more) are documented in [FAQ.md](FAQ.md).

## License

MIT
