local vars = require("hypr.vars")
local home = os.getenv("HOME")

hl.bind("SUPER + SHIFT + T", hl.dsp.exec_cmd(home .. "/.local/bin/theme-switcher.sh"),                 { description = "Theme Switcher" })
hl.bind("SUPER + SHIFT + W", hl.dsp.exec_cmd(home .. "/.local/bin/wallpaper-switcher.sh pick"),        { description = "Wallpaper Picker" })
hl.bind("SUPER + ALT + W",   hl.dsp.exec_cmd(home .. "/.local/bin/wallpaper-switcher.sh next"),        { description = "Next Wallpaper" })
hl.bind("SUPER + CTRL + W",  hl.dsp.exec_cmd(home .. "/.local/bin/live-wallpaper-toggle.sh"),          { description = "Toggle Live Wallpaper" })

hl.bind("SUPER + T", hl.dsp.exec_cmd(vars.terminal),       { description = "Terminal" })
hl.bind("SUPER + B", hl.dsp.exec_cmd(vars.browser),        { description = "Browser" })
hl.bind("SUPER + O", hl.dsp.exec_cmd(vars.notes),          { description = "Notes" })
hl.bind("SUPER + S", hl.dsp.exec_cmd(vars.androidstudio),  { description = "Android Studio" })
hl.bind("SUPER + F", hl.dsp.exec_cmd(vars.fileManager),    { description = "File Manager" })
hl.bind("SUPER + A", hl.dsp.exec_cmd(vars.menu),           { description = "App Launcher" })

hl.bind("SUPER + E", hl.dsp.exec_cmd("sh -c 'jome -d | wl-copy'"),                                              { description = "Emoji Picker" })
hl.bind("SUPER + V", hl.dsp.exec_cmd("sh -c 'cliphist list | rofi --show dmenu | cliphist decode | wl-copy'"),  { description = "Clipboard Manager" })
hl.bind("SUPER + M", hl.dsp.exec_cmd("sh -c '" .. vars.colorPicker .. " | wl-copy'"),                           { description = "Color Picker" })
