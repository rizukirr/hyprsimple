# FAQ

Troubleshooting notes for hyprsimple. Found a problem not covered here? Please [open an issue](https://github.com/rizukirr/hyprsimple/issues).

## How do I update hyprsimple, and will it overwrite my config?

```bash
hyprsimple-update
```

This pulls the latest hyprsimple, refreshes the helper scripts in `~/.local/bin`, installs any packages newly required by those scripts, and runs pending migrations.

**It never replaces your `~/.config`.** Customise those files freely. When a shipped default genuinely has to change, a migration makes that one specific edit, or calls `hyprsimple-refresh-config`, which saves your version as `<file>.bak.<timestamp>` and prints the diff before replacing it.

`install.sh` is a **first-time installer only**. It moves every existing `~/.config/<dir>` aside to `.backup` and copies fresh defaults, so re-running it on a configured machine will cost you your theme choice and any edits you have made. Use `hyprsimple-update` instead.

If you installed hyprsimple before it could update itself, run this **once** to get onto the update system. Unlike `install.sh` it leaves `~/.config` alone:

```bash
curl -fsSL https://raw.githubusercontent.com/rizukirr/hyprsimple/main/bootstrap.sh | bash
```

To reset a single file to the shipped default at any time:

```bash
hyprsimple-refresh-config hypr/hyprlock.conf
```

## The install ran without asking me anything. Can I watch what it does?

Yes. `./install.sh --interactive` restores every confirmation: the two `pacman -Syu` upgrades, the official package list, and each AUR package.

The default is unattended because the install takes a while and used to stop a dozen times across it, minutes apart, so it needed someone sitting in front of the machine for the whole run. It still asks for your sudo password once, at the start, and holds it for the rest of the install rather than letting it lapse and asking again halfway through.

The trade is real and worth knowing: an unattended `pacman -Syu` answers pacman's questions for you, including which packages to replace, and skips the Arch news. On a machine that has not been updated in a long time, use `--interactive` and read them.

## Connecting to WiFi says "secrets were required but not provided"

Fixed. `wifi 'Your Network'` now asks for the password when it needs one.

If you are on an install that predates the fix, run `hyprsimple-update`, or pass the password as a second argument, which has always worked:

```bash
wifi 'Your Network' 'your password'
```

The cause was that `nmcli` refuses to prompt for a secret unless it is given `--ask`, and the script never gave it, so joining a secured network for the first time failed with a message about `passwd-file`. A network that is open, or one already saved, was never affected.

Run from a keybind or a script rather than a terminal there is nobody to ask, so the two-argument form is still the way to do it unattended.

`wifi --help` lists both forms.

## `wl-screenrec-git` failed to build during install. Is recording broken?

No. `wf-recorder` comes from the official repositories, needs no build, and hyprsimple falls back to it when `wl-screenrec` is not installed. Recording keeps working with no action from you.

If the build failed with

```
error: linker `x86_64-linux-gnu-gcc` not found
```

the package is not the problem. Your Rust toolchain cannot link anything at all. Check it away from any AUR helper:

```bash
echo 'fn main() {}' > /tmp/t.rs && rustc /tmp/t.rs -o /tmp/t
```

If that fails the same way, every `cargo build` on the machine is broken, not just this one.

No `gcc` package ships a binary under that name. See for yourself:

```bash
pacman -Ql gcc | grep -E 'usr/bin/.*gcc$'
```

You get `gcc`, `x86_64-pc-linux-gnu-gcc`, and on CachyOS a `x86_64_v4-linux-gnu-gcc`, but never a plain `x86_64-linux-gnu-gcc`. A `rustc` that reaches for that name was built against a toolchain the machine does not have. The name is baked into the `rust` package rather than read from your config, so upgrading `gcc` or completing `base-devel` leaves it exactly as broken. It has turned up on `rust` from the `cachyos-extra-v4` repository.

Point cargo at a linker that does exist, in `~/.cargo/config.toml`:

```toml
[target.x86_64-unknown-linux-gnu]
linker = "cc"
```

That covers every `cargo build`, AUR builds included, because `makepkg` runs as you and reads your `~/.cargo`. Then build it if you want it:

```bash
paru -S wl-screenrec-git   # or yay -S
```

> [!NOTE]
> A cargo config does not reach bare `rustc`, so if you build Rust outside cargo, supply the missing name instead:
>
> ```bash
> sudo ln -s /usr/bin/gcc /usr/bin/x86_64-linux-gnu-gcc
> ```
>
> No package owns that symlink, so delete it once `rust` is rebuilt. Taking Arch's own build with `sudo pacman -S extra/rust` fixes it with no workaround to remember, at the cost of the CachyOS optimisations.

## My bluetooth headset is connected but the sound still comes out of the speakers

Fixed, and worth knowing why, because it is hyprsimple's own doing and it sticks.

WirePlumber chooses the default output by priority, and a bluetooth sink already outranks the built-in one. On the machine this was reported from, `priority.session` reads 1010 for the headset and 1009 for the speakers, so a headset takes over by itself on a fresh install.

What stops it is an explicitly chosen output. WirePlumber's `find-selected-default-node.lua` does

```lua
if current_configured_node == name then
  priority = 30000 + priority
```

to whatever `default.configured.audio.sink` names, so the chosen output scores 31009 and no bluetooth device can outrank it. `SUPER + F10` writes that key through `pactl set-default-sink`. Pressing the audio switch once therefore turned bluetooth auto-switching off permanently, on every machine, and nothing said so.

A user service now watches for a bluetooth output appearing and switches to it. Only on appearance, so a device already connected is left where it is, and switching away from it by hand is not undone.

If you are on an install that predates the fix, run `hyprsimple-update` and the migration enables it. To switch by hand in the meantime, press `SUPER + F10`, or:

```bash
wpctl set-default "$(pactl list short sinks | grep bluez_output | cut -f1 | head -1)"
```

To see what is pinned:

```bash
cat ~/.local/state/wireplumber/default-nodes
```

The `default.configured.audio.sink.0`, `.1` and so on below it are the previous choices, kept as a fallback chain for when the current one is gone.

To turn the auto-switching off:

```bash
systemctl --user disable --now hyprsimple-audio-autoswitch.service
```

## A migration failed. What now?

Migrations run once per machine, tracked in `~/.local/state/hyprsimple/migrations`. When one fails you are asked whether to skip it. Skipping records it under `.../migrations/skipped/` and continues.

To retry a skipped migration later, delete its marker and re-run:

```bash
rm ~/.local/state/hyprsimple/migrations/skipped/<timestamp>.sh
hyprsimple-migrate
```

Migrations are written to be idempotent, so re-running one whose fix you already have is a no-op. `hyprsimple-debug` reports which migrations are applied, skipped, and pending.

## How do I report a problem?

Run:

```bash
hyprsimple-debug
```

It collects your hyprsimple version and branch, migration state, hardware, Hyprland version and monitors, journal warnings, dmesg, the install log (`~/.local/state/hyprsimple/install.log`), and your explicitly installed packages into a single file, then offers to view, save, or upload it to `0x0.st` with a 24-hour expiry.

Attach the link to your [issue](https://github.com/rizukirr/hyprsimple/issues).

> [!NOTE]
> The report includes your hostname and package list. Review it before uploading. `hyprsimple-debug --print` dumps it to the terminal without uploading, and `--no-sudo` skips the dmesg section so you are not prompted for a password.

## Boot hangs with `[FAILED] Failed to start Load Kernel Modules`, then freezes after login (NVIDIA hybrid laptops)

On NVIDIA Optimus laptops (Intel/AMD iGPU + NVIDIA dGPU) running a bleeding-edge kernel (`linux-cachyos` 7.0.x with `nvidia-open`, for example), the NVIDIA driver's GSP firmware init can intermittently deadlock while the **initramfs** brings the dGPU up at boot. Symptoms:

- `[FAILED] Failed to start Load Kernel Modules` early in boot, followed by a long wait (a stuck `udev` / "Rule-based Manager for Device Events and Files" job).
- The login screen eventually appears, but the session freezes right after logging in.

The hang is in the kernel module load **inside the initramfs**, so userspace config (`/etc/modprobe.d`, `/etc/modules-load.d`) does **not** help unless the initramfs is rebuilt. The minimal fix is a kernel command-line parameter that stops the dGPU from loading at boot. It still loads on demand via `prime-run`, and the iGPU keeps driving the desktop, so Hyprland/Wayland is unaffected.

**Fix (systemd-boot):** add `modprobe.blacklist` for the NVIDIA modules to the affected kernel entry's `options` line in `/boot/loader/entries/<your-entry>.conf`:

```
options ... rw ... modprobe.blacklist=nvidia_drm,nvidia_modeset,nvidia_uvm,nvidia
```

Reboot into that entry. Verify:

```bash
lsmod | grep nvidia                          # empty at boot = good
prime-run glxinfo | grep "OpenGL renderer"   # still loads the dGPU on demand
```

> [!IMPORTANT]
> `prime-run` comes from `nvidia-prime` and `glxinfo` from `mesa-utils`. The installer now installs `nvidia-prime` alongside the driver, but it did not before, and `mesa-utils` is not installed at all. On an older install:
>
> ```bash
> sudo pacman -S --needed nvidia-prime mesa-utils
> ```

> [!NOTE]
> Scope the change to the bleeding-edge entry only, and leave your LTS entry untouched as a fallback. The community `nomodeset` workaround also boots, but disables **all** KMS (including the iGPU) and breaks Wayland. Blacklisting only NVIDIA with `modprobe.blacklist=nvidia*` avoids that. For GRUB, add the same `modprobe.blacklist=...` to `GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub`, then run `grub-mkconfig -o /boot/grub/grub.cfg`.
>
> On CachyOS the systemd-boot entries are **generated by `sdboot-manage`**, so a direct edit to `/boot/loader/entries/*.conf` is overwritten on the next `sudo sdboot-manage gen` (e.g. a kernel update). To make it persist, add the parameter to `LINUX_OPTIONS` in `/etc/sdboot-manage.conf` and run `sudo sdboot-manage gen`. This applies to **all** entries, so the dGPU loads on demand on the LTS kernel too. That is harmless, just no longer at boot.
>
> This is an upstream driver/kernel bug. Once a fixed `linux-cachyos` / `nvidia-open` update lands you can remove the parameter.
>
> Reference: [CachyOS forum: "Failed to start Load Kernel Modules and Rule-based Manager"](https://discuss.cachyos.org/t/failed-to-start-load-kernel-modules-and-rule-based-manager/27583)

## Stuck on a blank screen with a spinning loading circle after picking the OS in systemd-boot

This is the Plymouth boot splash hanging. It shows the spinner on a blank screen and never hands off to the login manager. Removing Plymouth fixes it (boot then shows plain text messages instead of the splash). On CachyOS the systemd-boot entries are generated by `sdboot-manage`, so the `splash`/`quiet` flags live in `/etc/sdboot-manage.conf` and `/etc/kernel/cmdline` rather than the entry files directly.

1. Uninstall Plymouth and its CachyOS theme/animation packages:
   ```bash
   sudo pacman -Rns plymouth cachyos-plymouth-theme cachyos-plymouth-bootanimation
   ```
2. Remove `splash` and `quiet` from `/etc/sdboot-manage.conf` (the `LINUX_OPTIONS=` line), then regenerate the boot entries:
   ```bash
   sudo sdboot-manage gen
   ```
3. Remove `plymouth` from the `HOOKS=(...)` line in `/etc/mkinitcpio.conf`, then rebuild the initramfs:
   ```bash
   sudo mkinitcpio -P
   ```
4. Remove `splash` and `quiet` from `/etc/kernel/cmdline` as well.

Verify after reboot. Boot should show plain systemd text with no spinner:

```bash
pacman -Q plymouth                # 'not found'
grep HOOKS /etc/mkinitcpio.conf   # no 'plymouth'
```

> [!NOTE]
> Reference: [CachyOS forum: "Disable or remove Plymouth boot splash"](https://discuss.cachyos.org/t/tutorial-disable-or-remove-plymouth-boot-splash/10922)

## Microphone sounds noisy / hissy on calls (RNNoise noise suppression)

hyprsimple ships an optional RNNoise filter that creates a virtual **"Noise Canceling source"**, a denoised copy of your microphone. It is provided by the `noise-suppression-for-voice` package and configured in `~/.config/pipewire/pipewire.conf.d/99-input-denoising.conf`.

This is **not** forced as your default input, so it never hijacks a USB, Bluetooth, or multi-mic setup. To start using it, pick it as the default mic. WirePlumber remembers the choice across reboots:

```bash
wpctl status                 # find the ID of "Noise Canceling source" (or your raw mic)
wpctl set-default <ID>       # WirePlumber remembers this across reboots
```

Tune aggressiveness via `"VAD Threshold (%)"` in the conf file, where higher cuts more noise but may clip the start of words. Reload with:

```bash
systemctl --user restart pipewire pipewire-pulse wireplumber
```

> [!NOTE]
> If your mic is **distorted/clipping** rather than just noisy, the cause is usually a hardware capture gain set too high, and RNNoise can't fix a clipped signal. Use `alsamixer` (F4 → Capture view) to lower **Capture** and any **Mic Boost** controls, then `sudo alsactl store` to persist. Bluetooth headset mics are a separate case: they only provide a mic in the low-quality HSP/HFP profile, so prefer a wired/built-in mic for input and keep the headset on A2DP for output.
>
> After any `pipewire` restart, also restart the portals or screen sharing can break until they reconnect: `systemctl --user restart xdg-desktop-portal xdg-desktop-portal-hyprland`
