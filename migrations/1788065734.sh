echo "Move dunst theme colours out of dunstrc and into a drop-in"

# theme-switcher.sh used to patch background, foreground and frame_color
# straight into ~/.config/dunst/dunstrc with sed. It now writes the theme's
# colours to dunstrc.d/90-theme.conf instead, which dunst applies on top of the
# base file. This migration writes that drop-in for the theme you are on, then
# puts dunstrc's colours back to the values hyprsimple ships, so the file is
# once again identical to the default for anyone who never edited it.
#
# It cannot tell a colour the old sed wrote from one you chose yourself, so it
# backs the file up first and prints where it went.

DUNST_DIR="$HOME/.config/dunst"
DUNSTRC="$DUNST_DIR/dunstrc"

[[ -f $DUNSTRC ]] || exit 0

mkdir -p "$DUNST_DIR/dunstrc.d"

# Carry the colours currently in force over to the drop-in. They are already in
# dunstrc, put there by the old sed, so nothing else has to be consulted: there
# is no persisted marker naming the theme you are on. Keep the section headers
# and the three colour keys, drop everything else.
#
# Guarded on the file not existing. A second run would otherwise rebuild the
# drop-in from a dunstrc this migration has already reset, replacing the theme
# colours with hyprsimple's defaults.
if [[ ! -e "$DUNST_DIR/dunstrc.d/90-theme.conf" ]]; then
  awk '
  /^[[:space:]]*\[/ { section = $0; printed = 0; next }
  /^[[:space:]]*(background|foreground|frame_color)[[:space:]]*=/ {
    if (!printed) { if (seen++) print ""; print section; printed = 1 }
    print
  }
' "$DUNSTRC" >"$DUNST_DIR/dunstrc.d/90-theme.conf"
  echo "Wrote $DUNST_DIR/dunstrc.d/90-theme.conf from the colours already in dunstrc"
fi

# Put the colour keys back to what hyprsimple shipped, so a dunstrc nobody
# edited is once again byte-identical to the default and the next migration can
# recognise it.
restored=$(mktemp)
awk '
  BEGIN {
    # The colours hyprsimple shipped in dunstrc before the drop-in split, keyed
    # by section and key. Literals, not a file read: a migration is a fixed
    # point in history, so it must not depend on a path a later commit is free
    # to repurpose, which is exactly what happened to .config/dunst/dunstrc.
    d["global",          "frame_color"] = "#a6adc8"
    d["urgency_low",     "background"]  = "#1e1e2e"
    d["urgency_low",     "foreground"]  = "#CDD6F4"
    d["urgency_normal",  "background"]  = "#1e1e2e"
    d["urgency_normal",  "foreground"]  = "#CDD6F4"
    d["urgency_critical","background"]  = "#1e1e2e"
    d["urgency_critical","foreground"]  = "#CDD6F4"
    d["urgency_critical","frame_color"] = "#FAB387"
  }
  /^[[:space:]]*\[/ {
    section = $0
    gsub(/^[[:space:]]*\[|\][[:space:]]*$/, "", section)
    print; next
  }
  {
    # Only a key this table names is reset. A colour key the user added
    # somewhere hyprsimple never shipped one is theirs, and is left alone.
    if (match($0, /^([[:space:]]*)(background|foreground|frame_color)[[:space:]]*=/)) {
      indent = $0; sub(/[^[:space:]].*$/, "", indent)
      key = $1
      if ((section SUBSEP key) in d) {
        printf "%s%s = \"%s\"\n", indent, key, d[section, key]
        next
      }
    }
    print
  }
' "$DUNSTRC" >"$restored"

if cmp -s "$restored" "$DUNSTRC"; then
  rm -f "$restored"
else
  backup="$DUNSTRC.bak.$(date +%s)"
  cp "$DUNSTRC" "$backup"
  cp "$restored" "$DUNSTRC"
  rm -f "$restored"
  echo "Reset the colours in $DUNSTRC to hyprsimple's defaults."
  echo "Your previous version is at $backup"
fi

if pgrep -x dunst >/dev/null; then
  pkill dunst
  uwsm app -- dunst &
fi
