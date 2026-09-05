echo "Rewrite hyprsunset.conf in the syntax hyprsunset actually reads"

# The shipped ~/.config/hypr/hyprsunset.conf used TOML tables:
#
#   [[profile]]
#   name = "day"
#   start_time = 07:00
#   identity = true
#
# hyprsunset reads hyprlang, the same syntax as the rest of hypr's configs, and
# rejected that outright. Measured with hyprsunset v0.4.0 against the shipped
# file: "Config error ... at line 7: Invalid config line", then "Loaded 0
# profiles", then a fall back to its own 6000K default. Uncommenting the night
# profile the file invited you to enable changed nothing, because no profile in
# it was ever read.
#
# Replaced only where the file is still byte-identical to a version hyprsimple
# shipped. Anything edited is left alone, because a hand-written TOML profile is
# still a record of what its author wanted even though hyprsunset ignores it.

user="$HOME/.config/hypr/hyprsunset.conf"
shipped="$HYPRSIMPLE_PATH/.config/hypr/hyprsunset.conf"

[[ -f $user && -f $shipped ]] || exit 0
cmp -s "$user" "$shipped" && exit 0

# Every version of this file the project shipped before the current one.
SHIPPED_SUMS=(
  290af9a61b2c12f96bacc3bced76a9ce
  e5ad8929e405b01fe6519fa19100bd80
)

sum=$(md5sum "$user" | cut -d' ' -f1)

for known in "${SHIPPED_SUMS[@]}"; do
  if [[ $sum == "$known" ]]; then
    cp -f "$user" "$user.bak"
    cp -f "$shipped" "$user"
    echo "  Updated $user (previous version kept at $user.bak)"
    echo "  Its profiles are read now. hyprsunset also starts with your session,"
    echo "  so uncommenting the night profile takes effect at your next login."
    exit 0
  fi
done

echo "  $user has your own edits, so it was left alone."
echo "  If it uses TOML tables such as [[profile]], hyprsunset cannot read them"
echo "  and loads no profiles at all. hyprsimple's version is hyprlang:"
echo "    hyprsimple-refresh-config.sh hypr/hyprsunset.conf"
