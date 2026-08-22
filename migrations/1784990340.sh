echo "Fix hyprlock hanging when the screen wakes up"

HYPRLOCK_CONF="$HOME/.config/hypr/hyprlock.conf"

[[ -f $HYPRLOCK_CONF ]] || exit 0

# Animations and the fail transition are what leave hyprlock stuck on a black
# screen after DPMS wake, and an empty input submit locks the field up.
if ! grep -q "ignore_empty_input" "$HYPRLOCK_CONF"; then
  sed -i '1a\
\
general {\
    ignore_empty_input = true\
}\
\
animations {\
    enabled = false\
}' "$HYPRLOCK_CONF"
fi

sed -i '/^\s*fail_transition\s*=/d' "$HYPRLOCK_CONF"

# Fingerprint auth blocks the unlock prompt when no finger is enrolled
if ! grep -q "fingerprint:enabled" "$HYPRLOCK_CONF"; then
  printf '\nauth {\n    fingerprint:enabled = false\n}\n' >>"$HYPRLOCK_CONF"
fi

# Cosmetic bits that shipped with the same fix
sed -i 's/^\(\s*placeholder_text\s*=\s*\)Input Password\s*$/\1Enter Password/' "$HYPRLOCK_CONF"

if ! grep -qE '^\s*rounding\s*=' "$HYPRLOCK_CONF"; then
  sed -i 's/^\(\s*\)hide_input = false$/\1hide_input = false\n\1rounding = 8/' "$HYPRLOCK_CONF"
fi
