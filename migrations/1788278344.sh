echo "Remove the unread copy of the theme templates from your home directory"

# Templates now come from the install, so ~/.config/hypr/themes/templates is no
# longer read at all. Leaving it there is harmless but misleading: it looks like
# the thing being rendered and is not.
#
# The directory is removed only when every file in it is byte-identical to some
# version this project shipped, which proves nothing in it was written by the
# user. A single unrecognised file leaves the whole directory alone, because a
# customised template is the one thing here worth keeping and its owner is told
# where it now belongs.

TPL="$HOME/.config/hypr/themes/templates"
USER_TPL="$HOME/.config/hypr/themes/templates.user"
[[ -d $TPL ]] || exit 0

# Every version of each template this project has shipped, from git history.
SHIPPED_SUMS=(
  3cd9a00a3fc011b0aa3d8beb5f32d0dc
  1b3ce88f8c8a7cb8e4f3498ef2464c30
  7ff17d249dac01bdf72a504155020617
  db181291a4aae21a0390328c710a4340
  66af45d722e9dcb49006a577144995ea
  216e8b8f3440d905c19a7893d8b08059
  921725a8b29c1306bbfb23afa1b18229
  edab07891813c11fa38845dc1fac41b1
  aed01ea1a0febd9ee4eec702187f46d9
  52330767a402caa38b17f66f8ccfe10f
  f30ed02d79c3f8be57da9a8c606cd489
)

is_shipped() {
  local sum
  sum=$(md5sum "$1" | cut -d' ' -f1)
  local s
  for s in "${SHIPPED_SUMS[@]}"; do
    [[ $sum == "$s" ]] && return 0
  done
  return 1
}

own=()
while IFS= read -r -d '' f; do
  is_shipped "$f" || own+=("$f")
done < <(find "$TPL" -type f -print0)

if [[ ${#own[@]} -gt 0 ]]; then
  echo ""
  echo "$TPL was left alone: these are not versions hyprsimple shipped."
  for f in "${own[@]}"; do
    echo "    ${f#"$HOME"/}"
  done
  echo ""
  echo "That directory is no longer read. To keep any of those, move them to"
  echo "    $USER_TPL/"
  echo "and delete the rest yourself."
  echo ""
  exit 0
fi

# Every file was one of ours, so nothing is lost. rm -rf is scoped to a path
# this migration built itself from $HOME, and the directory existence check
# above is what makes a re-run a no-op.
rm -rf "$TPL"
echo "Removed $TPL, which is no longer read."
