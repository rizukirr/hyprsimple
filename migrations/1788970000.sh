echo "Switch audio to a bluetooth device when one connects"

# WirePlumber picks the default sink by priority and a bluetooth sink already
# outranks the built-in one: 1010 against 1009, measured on the machine this was
# reported from. So on a fresh install a headset takes over by itself.
#
# What stops that is an explicitly chosen default. find-selected-default-node.lua
# in WirePlumber 0.5 adds 30000 to whatever default.configured.audio.sink names,
# so the chosen sink scores 31009 and no bluetooth device can outrank it.
# audio-switch.sh, on SUPER + F10, writes that key through
# `pactl set-default-sink`. Pressing the audio switch once therefore turned
# bluetooth auto-switching off for good, and nothing said so. Reported as a
# headset that connects, appears as a sink, and gets no sound.
#
# A watcher now sets a bluetooth sink as the default when one appears. Only on
# appearance, so a device already connected is left where it is and a switch
# away from it by hand is not undone.

UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/hyprsimple-audio-autoswitch.service"
SHIPPED="$HYPRSIMPLE_PATH/.config/systemd/user/hyprsimple-audio-autoswitch.service"

if [[ ! -f $SHIPPED ]]; then
  echo "  The unit is not in this install, so there is nothing to enable."
  exit 0
fi

# A file already there is either a previous run of this migration or someone's
# own, and neither is ours to overwrite. The unit is copied rather than
# symlinked because everything under ~/.config/systemd/user is yours to edit,
# which is what its header says.
if [[ -e $UNIT ]]; then
  echo "  You already have $UNIT, so it was left alone."
else
  mkdir -p "$UNIT_DIR"
  cp "$SHIPPED" "$UNIT"
fi

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable hyprsimple-audio-autoswitch.service &>/dev/null || true

# Started now only when a session is up. Run from a TTY there is nothing to
# watch and no bus to notify on.
if systemctl --user is-active graphical-session.target &>/dev/null; then
  systemctl --user start hyprsimple-audio-autoswitch.service &>/dev/null || true
  echo "  A bluetooth headset now takes over the sound when it connects."
else
  echo "  Enabled it. Your next login starts it."
fi

echo "  Turn it off with: systemctl --user disable --now hyprsimple-audio-autoswitch.service"
