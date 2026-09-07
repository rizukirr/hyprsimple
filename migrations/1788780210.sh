echo "Run hyprsunset as a service, so it comes back when it dies"

# hyprsunset was started by autostart.lua as `uwsm app -- hyprsunset`, a scope
# with no restart policy, and it does not survive a suspend. Measured across two
# cycles on one machine: started at login alongside dunst, hypridle and waybar,
# and the only one of the four gone afterwards, both times. Nothing brought it
# back, so every profile in hyprsunset.conf stopped applying for the rest of the
# session, including the scheduled night profile that file invites you to turn
# on.
#
# The hyprsunset package ships its own unit. hyprsimple now enables that,
# with a drop-in raising Restart from on-failure to always, because on-failure
# does not cover the clean exit hyprsunset makes when its output goes.
#
# The drop-in is a symlink into the install, like the dunst one, so a later
# change to it needs no migration of its own.

# Overridable so the suite can arrange a machine with and without hyprsunset
# installed. Without this the test depended on whatever the host happened to
# have, and passed here while doing nothing on a runner with no hyprsunset.
UNIT="${HYPRSIMPLE_SUNSET_UNIT:-/usr/lib/systemd/user/hyprsunset.service}"
DROPIN_DIR="$HOME/.config/systemd/user/hyprsunset.service.d"
DROPIN="$DROPIN_DIR/10-hyprsimple.conf"
SHIPPED="$HYPRSIMPLE_PATH/default/systemd/hyprsunset-restart.conf"

if [[ ! -f $UNIT ]]; then
  echo "  hyprsunset is not installed here, so there is nothing to enable."
  exit 0
fi

# Refused rather than clobbered, the same rule the delivery symlinks follow. A
# real file here is someone's own drop-in and is not ours to replace.
if [[ -e $DROPIN && ! -L $DROPIN ]]; then
  echo "  You have your own $DROPIN, so it was left alone."
  echo "  Add Restart=always under [Service] there if you want hyprsunset to come back on its own."
else
  mkdir -p "$DROPIN_DIR"
  ln -sfn "$SHIPPED" "$DROPIN"
fi

systemctl --user daemon-reload 2>/dev/null || true
systemctl --user enable hyprsunset.service &>/dev/null || true

# The old scope and the new unit cannot both hold hyprsunset's socket: a second
# instance exits at once. So the scope is stopped and the unit started in its
# place, rather than waiting for a logout. hyprsunset re-reads its profiles on
# start, so the screen ends up where the config says it should be.
#
# Only when a session is actually up. Run from a TTY there is nothing to hand
# over and nothing to start.
if systemctl --user is-active graphical-session.target &>/dev/null; then
  if pgrep -x hyprsunset >/dev/null; then
    pkill -x hyprsunset 2>/dev/null || true
    # Waited for, so the unit does not start into a socket the old process has
    # not let go of yet.
    waited=0
    while pgrep -x hyprsunset >/dev/null && ((waited < 50)); do
      sleep 0.1
      waited=$((waited + 1))
    done
  fi
  systemctl --user start hyprsunset.service &>/dev/null || true
  echo "  hyprsunset now runs as a service and restarts itself if it dies."
else
  echo "  Enabled hyprsunset.service. Your next login starts it."
fi
