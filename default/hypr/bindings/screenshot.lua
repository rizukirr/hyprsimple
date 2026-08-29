local home = os.getenv("HOME")

hl.bind("Print",              hl.dsp.exec_cmd(home .. "/.local/bin/screenshot.sh monitor"),   { description = "Screenshot Monitor" })
hl.bind("SUPER + Print",        hl.dsp.exec_cmd(home .. "/.local/bin/screenshot.sh window"),    { description = "Screenshot Window" })
hl.bind("SUPER + ALT + Print",  hl.dsp.exec_cmd(home .. "/.local/bin/screenshot.sh region"),    { description = "Screenshot Region" })
hl.bind("SUPER + CTRL + Print", hl.dsp.exec_cmd(home .. "/.local/bin/screenshot.sh clipboard"), { description = "Screenshot to Clipboard" })
