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
SHIPPED="$HYPRSIMPLE_PATH/.config/dunst/dunstrc"

[[ -f $DUNSTRC ]] || exit 0
[[ -f $SHIPPED ]] || exit 0

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

# Put the three colour keys back to what hyprsimple ships. Only these keys, and
# only when the shipped file actually defines them at that line.
restored=$(mktemp)
awk '
  NR == FNR { shipped[FNR] = $0; next }
  {
    line = $0
    # Same line number and the same key name on both sides. Matching on the key
    # rather than just "this is a colour line" means an added or removed line
    # upstream can only skip a reset, never write a background over a foreground.
    key = ""
    if (match($0, /^[[:space:]]*(background|foreground|frame_color)[[:space:]]*=/))
      key = $1
    skey = ""
    if (FNR in shipped && match(shipped[FNR], /^[[:space:]]*(background|foreground|frame_color)[[:space:]]*=/)) {
      split(shipped[FNR], f, /[[:space:]]+/)
      skey = (f[1] == "" ? f[2] : f[1])
    }
    if (key != "" && key == skey) line = shipped[FNR]
    print line
  }
' "$SHIPPED" "$DUNSTRC" >"$restored"

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
