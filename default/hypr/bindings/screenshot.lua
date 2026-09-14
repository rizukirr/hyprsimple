local home = os.getenv("HOME")

-- One key, and what to capture and where it goes are chosen from a list.
--
-- There were four binds here: Print, SUPER + Print, SUPER + ALT + Print and
-- SUPER + CTRL + Print. Three of those are chords nobody remembers, and the
-- keybinding viewer listed four entries for what is one action with two choices
-- in it. The menu also offers copying a region or a window, which no bind did.
hl.bind("Print", hl.dsp.exec_cmd(home .. "/.local/bin/hyprsimple-screenshot-menu.sh"),
  { description = "Screenshot (menu: region, window or screen, to file or clipboard)" })
