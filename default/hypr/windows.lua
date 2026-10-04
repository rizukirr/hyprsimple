-- =====================================================================
-- Top-level rules (was windows.conf)
-- =====================================================================
hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })
hl.window_rule({ match = { class = ".*" }, tag = "+default-opacity" })
hl.window_rule({
	match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
	no_focus = true,
})

-- =====================================================================
-- steam (was windows/steam.conf)
-- =====================================================================
hl.window_rule({ match = { class = "steam" }, float = true })
hl.window_rule({ match = { class = "steam", title = "Steam" }, center = true })
hl.window_rule({ match = { class = "steam.*" }, tag = "-default-opacity" })
hl.window_rule({ match = { class = "steam.*" }, opacity = "1 1" })
hl.window_rule({ match = { class = "steam", title = "Steam" }, size = { 1100, 700 } })
hl.window_rule({ match = { class = "steam", title = "Friends List" }, size = { 460, 800 } })
hl.window_rule({ match = { class = "steam" }, idle_inhibit = "fullscreen" })

-- =====================================================================
-- browser (was windows/browser.conf)
-- =====================================================================
hl.window_rule({
	match = { class = "((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)" },
	tag = "+chromium-based-browser",
})
hl.window_rule({
	match = { class = "([fF]irefox|zen|librewolf)" },
	tag = "+firefox-based-browser",
})
hl.window_rule({ match = { tag = "chromium-based-browser" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "firefox-based-browser" }, tag = "-default-opacity" })

-- Video apps: strip chromium-based-browser tag so they don't get opacity applied.
-- A site installed as an app has the class <browser>-<site>__-<profile>, so the
-- browser and the profile are left open: brave-youtube.com__-Default and
-- chrome-youtube.com__-Profile_1 are both the YouTube app.
hl.window_rule({
	match = { class = "(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)" },
	tag = "-chromium-based-browser",
})
hl.window_rule({
	match = { class = "(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)" },
	tag = "-default-opacity",
})

-- Hide the "<site> is sharing your screen" bar a browser shows while a call
-- has your screen.
--
-- The pattern used to be ".*is sharing.*", which is a workspace rule and so is
-- applied when a window opens. Any window whose title happened to contain
-- those two words was moved to a hidden workspace and appeared not to open at
-- all. Measured: a terminal titled "How Netflix is sharing your data" went
-- straight to special:special and was gone.
--
-- The six titles a chromium browser can give this bar, read out of Brave's own
-- en-US.pak, are
--
--   $1 is sharing your screen.            $1 is sharing a window.
--   $1 is sharing your screen and audio.  $1 is sharing a window and audio.
--   $1 is sharing a Brave tab.            $1 is sharing a Brave tab and audio.
--
-- so the object and the full stop are what tell the bar apart from prose. All
-- six still match. "is sharing your data" and "is sharing a document" no
-- longer do.
--
-- Narrowing rather than widening on purpose: if some browser words this
-- differently the bar reappears, which is visible and harmless, where the old
-- pattern lost you a window with no explanation.
hl.window_rule({
	match = { title = ".*is sharing (your screen|a window|a [A-Za-z]+ tab)( and audio)?\\..*" },
	workspace = "special silent",
})

-- Force chromium-based browsers into a tile (chromium --app bug workaround)
hl.window_rule({ match = { tag = "chromium-based-browser" }, tile = true })

-- Subtle opacity, but not for video sites
hl.window_rule({ match = { tag = "chromium-based-browser" }, opacity = "1.0 0.97" })
hl.window_rule({ match = { tag = "firefox-based-browser" }, opacity = "1.0 0.97" })

-- =====================================================================
-- terminal (was windows/terminal.conf)
-- =====================================================================
hl.window_rule({ match = { class = "(Alacritty|kitty|com.mitchellh.ghostty)" }, tag = "+terminal" })
hl.window_rule({ match = { tag = "terminal" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "terminal" }, opacity = "0.97 0.9" })

-- =====================================================================
-- webcam (was windows/webcam.conf)
-- =====================================================================
hl.window_rule({ match = { title = "WebcamOverlay" }, float = true })
hl.window_rule({ match = { title = "WebcamOverlay" }, pin = true })
hl.window_rule({ match = { title = "WebcamOverlay" }, no_initial_focus = true })
hl.window_rule({ match = { title = "WebcamOverlay" }, no_dim = true })
hl.window_rule({ match = { title = "WebcamOverlay" }, move = "(monitor_w-window_w-40) (monitor_h-window_h-40)" })

-- =====================================================================
-- system (was windows/system.conf)
-- =====================================================================
hl.window_rule({ match = { tag = "floating-window" }, float = true })
hl.window_rule({ match = { tag = "floating-window" }, center = true })
hl.window_rule({ match = { tag = "floating-window" }, size = { 875, 600 } })

-- Float the Nautilus file manager by default (main window + Open/Save dialogs)
hl.window_rule({ match = { class = "org.gnome.Nautilus" }, tag = "+floating-window" })

-- The portal only ever shows dialogs: file pickers, screen shares, permission
-- prompts. Every one of its windows floats, whatever the app that asked for it
-- titled it and in whatever language.
hl.window_rule({ match = { class = "xdg-desktop-portal-gtk" }, tag = "+floating-window" })

-- These apps draw their own file dialogs under their main window's class, so
-- the title is what tells a dialog from the app.
hl.window_rule({
	match = {
		class = "(sublime_text|DesktopEditors)",
		title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
	},
	tag = "+floating-window",
})
hl.window_rule({ match = { class = "org.gnome.Calculator" }, float = true })

-- No transparency on media windows
hl.window_rule({
	match = {
		class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
	},
	tag = "-default-opacity",
})
hl.window_rule({
	match = {
		class = "^(zoom|vlc|mpv|org.kde.kdenlive|com.obsproject.Studio|com.github.PintaProject.Pinta|imv|org.gnome.NautilusPreviewer)$",
	},
	opacity = "1 1",
})

-- Pop / no-idle tags
hl.window_rule({ match = { tag = "pop" }, rounding = 4 })
hl.window_rule({ match = { tag = "noidle" }, idle_inhibit = "always" })

-- =====================================================================
-- viewer (was windows/viewer.conf) — empty / TODO swayimg float
-- =====================================================================

-- =====================================================================
-- geforce (was windows/geforce.conf)
-- =====================================================================
hl.window_rule({
	name = "geforce",
	match = { class = "GeForceNOW" },
	idle_inhibit = "fullscreen",
})

-- =====================================================================
-- jetbrains (was windows/jetbrains.conf)
-- =====================================================================
-- One rule, and it only concerns focus. The IDE places and sizes its own
-- popups, and a rule that centres or resizes its untitled windows takes a menu
-- away from the thing it was opened on.
hl.window_rule({
	name = "jetbrains-focus",
	match = { class = "^(jetbrains-.*)$" },
	no_follow_mouse = true,
})

-- =====================================================================
-- qemu (was windows/qemu.conf)
-- =====================================================================
hl.window_rule({ match = { class = "qemu" }, tag = "-default-opacity" })
hl.window_rule({ match = { class = "qemu" }, opacity = "1 1" })

-- =====================================================================
-- emulator (was windows/emulator.conf)
-- =====================================================================
-- Floated and not centred. Qt titles this app's popups "Emulator" as well, so
-- the rule matches a combo box list, and center would take it away from the
-- box it belongs to and open it in the middle of the screen.
hl.window_rule({ match = { class = "^(Emulator)$", title = "^(Emulator)$" }, float = true })
hl.window_rule({ match = { class = "^(Android Emulator)$", title = "^(Android Emulator.*)$" }, float = true })
hl.window_rule({ match = { class = "^(Android Emulator)$", title = "^(Android Emulator.*)$" }, center = true })

-- =====================================================================
-- pip (was windows/pip.conf)
-- =====================================================================
hl.window_rule({ match = { title = "(Picture.?in.?[Pp]icture)" }, tag = "+pip" })
hl.window_rule({ match = { tag = "pip" }, tag = "-default-opacity" })
hl.window_rule({ match = { tag = "pip" }, float = true })
hl.window_rule({ match = { tag = "pip" }, pin = true })
hl.window_rule({ match = { tag = "pip" }, size = { 600, 338 } })
hl.window_rule({ match = { tag = "pip" }, keep_aspect_ratio = true })
hl.window_rule({ match = { tag = "pip" }, border_size = 0 })
hl.window_rule({ match = { tag = "pip" }, opacity = "1 1" })
-- 600 is the width set above, written out. window_w here is the width the
-- window arrived with, before the size rule, so a position worked out from it
-- puts a window that arrived narrower past the right edge.
hl.window_rule({ match = { tag = "pip" }, move = "(monitor_w-600-40) (monitor_h*0.04)" })

-- =====================================================================
-- moonlight (was windows/moonlight.conf)
-- =====================================================================
hl.window_rule({ match = { class = "com.moonlight_stream.Moonlight" }, fullscreen = true })
hl.window_rule({ match = { class = "com.moonlight_stream.Moonlight" }, idle_inhibit = "fullscreen" })

-- =====================================================================
-- retroarch (was windows/retroarch.conf)
-- =====================================================================
hl.window_rule({ match = { class = "com.libretro.RetroArch" }, fullscreen = true })
hl.window_rule({ match = { class = "com.libretro.RetroArch" }, tag = "-default-opacity" })
hl.window_rule({ match = { class = "com.libretro.RetroArch" }, opacity = "1 1" })
hl.window_rule({ match = { class = "com.libretro.RetroArch" }, idle_inhibit = "fullscreen" })

-- =====================================================================
-- davinci-resolve (was windows/davinci-resolve.conf)
-- =====================================================================
hl.window_rule({ match = { class = ".*[Rr]esolve.*", float = true }, stay_focused = true })

-- =====================================================================
-- localsend (was windows/localsend.conf)
-- =====================================================================
hl.window_rule({ match = { class = "(Share|localsend)" }, float = true })
hl.window_rule({ match = { class = "(Share|localsend)" }, center = true })
hl.window_rule({ match = { class = "localsend" }, size = { 1100, 700 } })

-- =====================================================================
-- telegram (was windows/telegram.conf)
-- =====================================================================
hl.window_rule({ match = { class = "org.telegram.desktop" }, focus_on_activate = false })

-- =====================================================================
-- hyprshot (was windows/hyprshot.conf) — layer rule
-- =====================================================================
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true })

-- =====================================================================
-- the bar's panels and launcher — layer rule
-- =====================================================================
-- They animate themselves. Hyprland's own layer animation on top of that
-- played a second fade as each one opened and closed, which made closing the
-- launcher look as if it happened twice.
hl.layer_rule({ match = { namespace = "quickshell-panel" }, no_anim = true })

-- =====================================================================
-- Apply default opacity after apps have had a chance to opt out
-- (was the trailing line in windows.conf)
-- =====================================================================
hl.window_rule({ match = { tag = "default-opacity" }, opacity = "0.97 0.9" })
