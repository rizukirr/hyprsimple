local home = os.getenv("HOME")
local rec  = home .. "/.local/bin/screen-record.sh"

hl.bind("SUPER + R",               hl.dsp.exec_cmd(rec .. " region mic"),      { description = "Record Region (Mic)" })
hl.bind("SUPER + SHIFT + R",       hl.dsp.exec_cmd(rec .. " output mic"),      { description = "Record Screen (Mic)" })
hl.bind("SUPER + ALT + R",         hl.dsp.exec_cmd(rec .. " region internal"), { description = "Record Region (System Audio)" })
hl.bind("SUPER + SHIFT + ALT + R", hl.dsp.exec_cmd(rec .. " output internal"), { description = "Record Screen (System Audio)" })
hl.bind("SUPER + CTRL + R",        hl.dsp.exec_cmd(rec .. " region none"),     { description = "Record Region (No Audio)" })
hl.bind("SUPER + CTRL + SHIFT + R",hl.dsp.exec_cmd(rec .. " output none"),     { description = "Record Screen (No Audio)" })
