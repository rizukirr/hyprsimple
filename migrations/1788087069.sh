echo "Add the screen recording indicator to waybar"

# waybar's config is not split: its module lists are arrays, so an include
# cannot add one module without restating the whole list. Updates arrive by
# explicit reset instead, through hyprsimple-refresh-waybar.
#
# A file is refreshed here only when it is byte-identical to something
# hyprsimple shipped, which proves it was never edited. Anything else is left
# exactly as it is, and the command to refresh it is printed instead.

WAYBAR="$HOME/.config/waybar"
[[ -d $WAYBAR ]] || exit 0

CONFIG_SUMS=(
  07ee330f737f1655ba9fe62632e4f6a8
  09d5a55da106542ebb2621515c76b291
  1dcda3be15ccee1c88d4feb3be6bda5d
  2a2740850b891235ff76d95ba25df500
  2d03648c3972814b9657ccab576f26ea
  4e06ee464f5350f635c07a6e9d485d04
  50e9f99b6a1cc5a65f49615b0a3b7151
  55a3c955b0498cee29032ffb2354b10c
  7095e813fbc4e43ba663d0af51fcb9f4
  71cacc1842185b972e60fe9e21fd9a6f
  8291a8c1038b7875b22ce17ccaa7545b
  84d2e2105e25b6aeddf75dc999721050
  9bac31018660d404a4a51d3529616dbc
  a54ec3dd7c9efd3cc3756b1c90d3c803
  adb781665e3c36084bf365009ff757df
  c751c395316fc0750c2f2b09770a2e91
  f53cdf586c0b2bee96cbccbd74f20b06
)
STYLE_SUMS=(
  0041768b8c6626ebfb25b5799e453cf9
  4058a2d6734eadb406fb498fc58b5efc
  4da8f6885f7708545081bbcbe66807d0
  696b0ea77ae5d87a4bd948fa419abc6e
  70f6efb9868fedc57291fc5da85ec7b5
  8382bad43079231d00dbe54c0d78ac37
  839b61b5921029dac5dbe4097123d7e7
  dcce85712d7d9590191c1c2987c31df0
  ddacad72b961e74605d874589c30c12f
  e1df5208a1b35c6a3d0cd69cc2abc24a
  e2198939a76eb765ce6d7bf12725b732
)

refresh_if_pristine() {
  local name="$1"
  shift
  local user="$WAYBAR/$name"
  local shipped="$HYPRSIMPLE_PATH/.config/waybar/$name"

  [[ -f $user && -f $shipped ]] || return 0
  cmp -s "$user" "$shipped" && return 0

  local sum
  sum=$(md5sum "$user" | cut -d' ' -f1)
  local s
  for s in "$@"; do
    if [[ $sum == "$s" ]]; then
      cp "$shipped" "$user"
      echo "Updated $user"
      return 0
    fi
  done

  echo ""
  echo "$user has your own edits, so it was left alone."
  echo "It does not yet have the screen recording indicator. To take hyprsimple's"
  echo "current version, keeping your bar position and a backup of your file:"
  echo ""
  echo "    hyprsimple-refresh-waybar.sh"
  echo ""
  echo "What that would change:"
  diff "$user" "$shipped" || true
}

refresh_if_pristine config.jsonc "${CONFIG_SUMS[@]}"
refresh_if_pristine style.css "${STYLE_SUMS[@]}"

"$HOME/.local/bin/hyprsimple-restart-waybar.sh"
