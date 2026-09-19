# Making your own theme

A theme in hyprsimple is one directory of colours. You write sixteen palette entries and a few named colours into `colors.toml`, and a theme switch renders them into waybar, rofi, dunst, hyprlock, ghostty, btop and Hyprland's own borders, then reloads each of those programs.

Everything here happens in `~/.config/hypr/themes/`, which is yours. hyprsimple copies it once at install and never overwrites it, so a theme you add stays through every update.

## The short version

```bash
cd ~/.config/hypr/themes
cp -r deep-sea my-theme
$EDITOR my-theme/colors.toml
theme-switcher.sh my-theme
```

Pick a wallpaper for it with `SUPER + SHIFT + W`, or drop images into `my-theme/backgrounds/`. Your theme then appears in the picker on `SUPER + SHIFT + T` alongside the shipped ones.

## What goes in the directory

Only `colors.toml` is required. Everything else has a sensible default.

| Path | What it does |
| --- | --- |
| `colors.toml` | The palette. Without it nothing is generated and the theme applies no colours. |
| `backgrounds/` | Wallpapers, as jpg, jpeg, png or webp. The first one in sorted order is applied on switch, and `SUPER + ALT + W` cycles the rest. |
| `light.mode` | An empty file. Its presence puts GTK and Qt into light mode and uses Adwaita rather than Adwaita-dark. |
| `icon-theme` | One line naming an icon theme, such as `Yaru-blue`. Applied with gsettings. `icons.theme` is read too, for themes that came from omarchy. |
| `ghostty-theme` | One line naming a theme ghostty already ships, such as `Gruvbox Light`. With this file the terminal uses ghostty's own copy of the scheme and the generated palette is skipped. Run `ghostty +list-themes` to see the names. |
| `lockscreen.*` | An image for hyprlock. Without it the wallpaper is used. |

## colors.toml

Hex strings, six digits, with the leading `#`. These are the keys the renderer reads:

```toml
accent = "#1A76C9"
cursor = "#ffffff"
foreground = "#F9F8FE"
background = "#010a1a"
selection_foreground = "#010a1a"
selection_background = "#ffb703"

color0  = "#051f42"   # black, and the usual source of widget surfaces
color1  = "#ff5d5d"   # red, used for danger
color2  = "#1F7DD3"   # green, used for success
color3  = "#ffcc00"   # yellow, used for warnings and the calendar weekday
color4  = "#1e6091"   # blue, used for a dimmer accent
color5  = "#9d4edd"   # magenta, used for the calendar day and secondary text
color6  = "#1E4BC3"   # cyan, used for informational text
color7  = "#1A76C9"   # white, used for borders
color8  = "#184e77"   # bright black, used for muted and placeholder text
color9  = "#ff5d5d"   # bright red
color10 = "#0F50A5"   # bright green
color11 = "#ffb703"   # bright yellow
color12 = "#1a759f"   # bright blue
color13 = "#5E6FDD"   # bright magenta
color14 = "#2A93DD"   # bright cyan
color15 = "#ffffff"   # bright white
```

The sixteen palette entries reach the terminal exactly as you write them. They are never adjusted, because a scheme's own black really is black and its own white really is white, and a terminal is expected to show them that way.

The interface is a different matter, and hyprsimple computes it for you.

## The colours you do not write

Two kinds of colour are derived from the palette rather than taken from it.

The widget surface, which is what the waybar pills sit on. `color0` is used where it reads against the text and is not far from the background. Otherwise the surface is the background lifted twelve percent towards the foreground, which keeps it the theme's own colour and works the same way on a light theme as on a dark one.

The interface colours, which are the palette entries above nudged until they can actually be read on what they are drawn on. Success, warning, danger, info, secondary and the accent are checked against the widget surface. The calendar day and weekday are checked against the background. Muted text and borders are checked at a lower bar, because they are meant to be quiet rather than invisible.

A colour that already reads is returned untouched, and a colour that does not keeps its hue while its lightness moves, towards white on a dark surface and towards black on a light one. So a theme keeps its character and its text stays readable on every surface it lands on.

You do not have to do anything to get this. Write a palette you like and the interface follows.

## What gets generated, and where it lands

Rendering writes into `<theme>/generated/`, and a switch puts each file where its program reads it:

| Generated file | Where it goes |
| --- | --- |
| `waybar-colors.css` | symlinked to `~/.config/waybar/theme-active.css` |
| `theme-clock.jsonc` | symlinked to `~/.config/waybar/theme-clock.jsonc`, the calendar colours |
| `rofi-colors.rasi` | symlinked to `~/.config/rofi/rofi-colors.rasi` |
| `dunst-colors` | copied to `~/.config/dunst/dunstrc.d/90-theme.conf` |
| `hyprland-colors.lua` | symlinked to `~/.config/hypr/theme-active.lua`, the window borders |
| `hyprlock.conf` | copied to `~/.config/hypr/theme-hyprlock.conf` |
| `ghostty.conf` | appended to `~/.config/ghostty/config`, unless the theme has a `ghostty-theme` file |
| `btop.theme` | copied to `~/.config/btop/themes/current.theme`, and btop is pointed at it |

Nothing in `generated/` is worth editing. It is overwritten on every switch and on every update that changes a template.

## Trying it out

```bash
theme-switcher.sh my-theme                              # apply it
theme-apply-templates.sh ~/.config/hypr/themes/my-theme  # re-render without switching
```

A switch re-renders first, so editing `colors.toml` and switching again is enough while you are working on it. The keybinding for the picker is `SUPER + SHIFT + T`, and `SUPER + SHIFT + W` picks a wallpaper within the current theme.

If the change does not show, the program probably needs its config reread. Switching again is the blunt way. waybar and dunst can also be restarted on their own with `hyprsimple-restart-waybar.sh` and `systemctl --user restart dunst`.

## Changing how a colour is used

The mapping from palette to interface lives in templates, one per program, in `~/.local/share/hyprsimple/.config/hypr/themes/templates/`. They are plain text with `{{ key }}` placeholders, where `key` is any name from `colors.toml` or any of the derived names such as `surface` or `ui_danger`. Two variants exist for each: `{{ key_strip }}` drops the leading `#`, and `{{ key_rgb }}` gives `30,30,46`.

The install owns those files, so a template change from hyprsimple reaches you on the next update. To change one yourself, copy it into `~/.config/hypr/themes/templates.user/` under the same name and edit it there. That directory wins over the install, and a template in it with no shipped counterpart is rendered too, so you can add outputs of your own.

Editing the shipped templates in place does nothing: they are replaced on update.

## Your theme and updates

An update never touches a theme hyprsimple does not ship. The catalogue migration adds themes that are missing and removes the eight that came from omarchy, and only when their `colors.toml` is still byte-identical to what was shipped. A theme of your own is not in either list.

The one thing an update does reach into is `generated/`, which is re-rendered when the templates change. Since that directory is output, nothing of yours is lost.

## Sharing it

Themes live in `.config/hypr/themes/` in the repository, with the same layout as above. Two things to know before opening a pull request:

Wallpapers have to pass the image policy, which CI checks on every pull request that touches themes. Run `bin/hyprsimple-dev-optimize-images` and it will fix what it can.

`test/theme-catalogue-test.sh` checks the catalogue: a `colors.toml` with the keys the templates need, swatches distinct enough to tell themes apart in the picker, an icon theme hyprsimple installs, at least one wallpaper of its own that is not an absolute symlink, `light.mode` matching what the background luminance says, and enough contrast in waybar and rofi between the text and what it sits on. Run it before pushing and it names whichever of those a new theme is missing.

If the scheme is a well known one, taking the palette from that project's own ghostty theme in `/usr/share/ghostty/themes/` gives you the colours its authors publish rather than an approximation.
