echo "Show Hypri as the fastfetch logo"

# fastfetch printed an ASCII logo from ~/.config/fastfetch/ascii.txt. It now
# shows Hypri, the mascot, from Hypri.png beside it. Both files are copied once
# at install and the config promises it is yours, so this only switches an
# install whose config.jsonc and ascii.txt are still exactly as hyprsimple
# shipped them, proven by checksum against every version that ever shipped.
# Anyone who changed either keeps theirs and is told how to opt in.

DIR="$HOME/.config/fastfetch"
SHIPPED="$HYPRSIMPLE_PATH/.config/fastfetch"

# md5 of each config.jsonc and ascii.txt hyprsimple has shipped.
SHIPPED_CONFIGS="
  2bd4f45c24e708947ff9dfa20fee7e9a
  49533476ee52f44e99061d6e3ff4f368
  92fc56750068f0d5201b4e3fd70834e1
  cb7d10d29c3ff27ddfda288eabe4d3f5
"
SHIPPED_ASCII="98ae2712b0effa799f0c7981fe37fc40"

if [[ ! -d $DIR ]]; then
  echo "  No fastfetch config here, so there is nothing to change."
  exit 0
fi

if [[ ! -f $SHIPPED/Hypri.png || ! -f $SHIPPED/config.jsonc ]]; then
  echo "  This install does not ship the new logo, so nothing was changed."
  exit 0
fi

# The picture goes in first, whatever happens to the config, so the opt-in
# command below has something to point at. Copied under a temporary name and
# moved into place, so an interrupted copy never leaves half a picture.
if [[ ! -f $DIR/Hypri.png ]]; then
  cp "$SHIPPED/Hypri.png" "$DIR/.Hypri.png.partial" || exit 1
  mv "$DIR/.Hypri.png.partial" "$DIR/Hypri.png" || exit 1
fi

if [[ -f $DIR/config.jsonc ]] && grep -q 'fastfetch/Hypri.png' "$DIR/config.jsonc"; then
  echo "  fastfetch already shows Hypri."
  exit 0
fi

md5() { md5sum "$1" | cut -d' ' -f1; }

config_untouched=false
if [[ ! -f $DIR/config.jsonc ]] || grep -qx "  $(md5 "$DIR/config.jsonc")" <<<"$SHIPPED_CONFIGS"; then
  config_untouched=true
fi
ascii_untouched=false
if [[ ! -f $DIR/ascii.txt ]] || [[ $(md5 "$DIR/ascii.txt") == "$SHIPPED_ASCII" ]]; then
  ascii_untouched=true
fi

if [[ $config_untouched != true || $ascii_untouched != true ]]; then
  echo "  Your fastfetch config or logo has your own changes, so both were left as they are."
  echo "  To show Hypri instead, run: hyprsimple-refresh-config.sh fastfetch/config.jsonc"
  exit 0
fi

# Copied directly rather than through hyprsimple-refresh-config.sh, whose job is
# to keep a backup of edits. The checksum proved there are none, so a backup
# would only be clutter.
cp "$SHIPPED/config.jsonc" "$DIR/.config.jsonc.partial" || exit 1
mv "$DIR/.config.jsonc.partial" "$DIR/config.jsonc" || exit 1
rm -f "$DIR/ascii.txt"

if ! grep -q 'fastfetch/Hypri.png' "$DIR/config.jsonc" || [[ ! -f $DIR/Hypri.png ]]; then
  echo "  The fastfetch logo did not switch to Hypri." >&2
  exit 1
fi

echo "  fastfetch now shows Hypri. The ASCII logo it replaces is removed."
