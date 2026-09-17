echo "Make microphone noise suppression follow the microphone you choose"

# The noise filter captured from the default microphone and offered its result
# as a separate source, "Noise Canceling source". Choosing a microphone meant
# making that microphone the default, and applications recording from the
# default then heard it raw, with no suppression at all. Measured on the machine
# this was reported from: the default source was the bluetooth headset's
# microphone, and nothing was going through the filter.
#
# It is a WirePlumber smart filter now. WirePlumber places it in front of the
# default microphone, so choosing one with SUPER + S keeps suppression on it.
#
# The file is yours, so it is replaced only where it is still byte-identical to
# a version hyprsimple shipped. Anything else is left alone and the two lines to
# add are printed.

REL="pipewire/pipewire.conf.d/99-input-denoising.conf"
USER_FILE="$HOME/.config/$REL"
SHIPPED="$HYPRSIMPLE_PATH/.config/$REL"

# md5 of every version shipped before this one, oldest first.
SHIPPED_BEFORE="
  90ead7b789f01dc2d6957590bbe98669
  ae57d3fac4c5b092cad0c585421a99ee
  1f3e7f5f16d12fe969c894ae85ee6fff
"

if [[ ! -f $USER_FILE ]]; then
  echo "  No noise suppression config here, so there is nothing to change."
  exit 0
fi

if [[ ! -f $SHIPPED ]]; then
  echo "  The shipped config is missing from this install, so nothing was changed."
  exit 0
fi

if ! cmp -s "$USER_FILE" "$SHIPPED"; then
  sum=$(md5sum "$USER_FILE" | cut -d' ' -f1)
  if grep -qx "[[:space:]]*$sum" <<<"$SHIPPED_BEFORE"; then
    cp -f "$SHIPPED" "$USER_FILE"
    echo "  Updated $USER_FILE."
  else
    echo "  You have your own version of $USER_FILE, so it was left alone."
    echo "  To make suppression follow the microphone you choose, add these under playback.props:"
    echo "    filter.smart = true"
    echo "    filter.smart.name = \"hyprsimple.rnnoise\""
    exit 0
  fi
fi

# A default microphone pinned to the filter itself is moved to a real one.
#
# WirePlumber never picks a smart filter as the default on its own, but a pin
# written before this change can still name it, and a filter that follows the
# default microphone cannot also be that microphone. Only done with a session
# up, because pactl has nothing to talk to from a TTY.
if systemctl --user is-active graphical-session.target &>/dev/null &&
  command -v pactl >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
  if [[ $(pactl get-default-source 2>/dev/null) == rnnoise_source ]]; then
    best=$(pactl -f json list sources 2>/dev/null | jq -r '
      [.[] | select(.properties["device.api"] != null)
           | select(.name | endswith(".monitor") | not)]
      | sort_by(.properties["priority.session"] // "0" | tonumber)
      | last | .name // empty' 2>/dev/null)
    if [[ -n $best ]] && pactl set-default-source "$best" 2>/dev/null; then
      echo "  Your default microphone was the filter itself, so it is now $best."
    fi
  fi
fi

echo "  Takes effect at your next login, or now with:"
echo "    systemctl --user restart pipewire pipewire-pulse wireplumber"
