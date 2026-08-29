-- See https://wiki.hypr.land/Configuring/Basics/Variables/

hl.config({
	general = {
		gaps_in = 5,
		gaps_out = { top = 10, right = 10, bottom = 10, left = 10 },
		border_size = 1,
		resize_on_border = true,
		allow_tearing = false,
		-- layout = "dwindle",
	},
	decoration = {
		rounding = 12,
		active_opacity = 1.0,
		inactive_opacity = 0.7,
		blur = {
			enabled = true,
			size = 5,
			passes = 3,
			new_optimizations = true,
			vibrancy = 0.1696,
			ignore_opacity = false,
		},
	},
	animations = {
		enabled = true,
	},
	master = {},
	misc = {
		force_default_wallpaper = 0,
		disable_hyprland_logo = true,
		disable_splash_rendering = true,
		vrr = 0,
		-- Open new windows (e.g. portal file pickers) on the active workspace
		-- instead of the workspace their parent process was launched on.
		initial_workspace_tracking = 0,
	},
})

-- Bezier curves
hl.curve("wind", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("winIn", { type = "bezier", points = { { 0.1, 1.1 }, { 0.1, 1.1 } } })
hl.curve("winOut", { type = "bezier", points = { { 0.3, -0.3 }, { 0, 1 } } })
hl.curve("liner", { type = "bezier", points = { { 1, 1 }, { 1, 1 } } })

-- Animations
hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "wind", style = "slide" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 3, bezier = "winIn", style = "slide" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 2, bezier = "winOut", style = "slide" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 2, bezier = "wind", style = "slide" })
hl.animation({ leaf = "border", enabled = true, speed = 1, bezier = "liner" })
hl.animation({ leaf = "borderangle", enabled = true, speed = 30, bezier = "liner", style = "loop" })
hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "default" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1, bezier = "wind" })
