local home = os.getenv("HOME")

-- One key and no menu. Print freezes the screen and shows a picker: drag for a
-- region, click a window for that window, click where there is none for the
-- whole monitor, Escape for nothing. The picture is saved and copied, both.
--
-- There were four binds here once, three of them chords nobody remembers, and
-- then a menu that asked what to capture and where to put it before anything
-- could be picked. The picker answers the first question by what is done with
-- the pointer, and doing both answers the second.
hl.bind("Print", hl.dsp.exec_cmd(home .. "/.local/bin/screenshot.sh smart"),
  { description = "Screenshot (drag a region, or click a window or the screen)" })
