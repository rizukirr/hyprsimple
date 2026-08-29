hl.bind("SUPER + Q", hl.dsp.window.close(),                       { description = "Close Window" })
hl.bind("SUPER + W", hl.dsp.window.float({ action = "toggle" }),  { description = "Toggle Floating" })
-- hl.bind("SUPER + SHIFT + J", hl.dsp.layout("togglesplit"),     { description = "Toggle Split" })

-- Move focus (vim-style)
hl.bind("SUPER + H", hl.dsp.focus({ direction = "l" }), { description = "Focus Left" })
hl.bind("SUPER + L", hl.dsp.focus({ direction = "r" }), { description = "Focus Right" })
hl.bind("SUPER + K", hl.dsp.focus({ direction = "u" }), { description = "Focus Up" })
hl.bind("SUPER + J", hl.dsp.focus({ direction = "d" }), { description = "Focus Down" })

-- Resize active window (repeating)
hl.bind("SUPER + SHIFT + RIGHT", hl.dsp.window.resize({ x =  30, y = 0,   relative = true }), { description = "Resize Right", repeating = true })
hl.bind("SUPER + SHIFT + LEFT",  hl.dsp.window.resize({ x = -30, y = 0,   relative = true }), { description = "Resize Left",  repeating = true })
hl.bind("SUPER + SHIFT + UP",    hl.dsp.window.resize({ x =   0, y = -30, relative = true }), { description = "Resize Up",    repeating = true })
hl.bind("SUPER + SHIFT + DOWN",  hl.dsp.window.resize({ x =   0, y =  30, relative = true }), { description = "Resize Down",  repeating = true })

-- Move/resize with mouse drag
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(),   { mouse = true, description = "Move Window" })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Resize Window" })
