local home = os.getenv("HOME")

-- One key, and the combination is chosen from a list.
--
-- There were six binds here, one per pairing of scope and audio source:
-- SUPER + R, + SHIFT, + ALT, + SHIFT + ALT, + CTRL, + CTRL + SHIFT. Five of
-- those are chords nobody remembers, and the keybinding viewer listed all six
-- as separate entries for what is one action with two choices in it.
--
-- The menu also stops a recording that is running, so the same key both starts
-- and stops and there is nothing to remember about which.
hl.bind("SUPER + R", hl.dsp.exec_cmd(home .. "/.local/bin/hyprsimple-record-menu.sh"),
  { description = "Record (menu: region or screen, mic, system audio or none)" })
