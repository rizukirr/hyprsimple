echo "Remove the unused ~/.local/share/wallpapers directory"

# hyprsimple shipped three wallpapers in .local/share/wallpapers that no script
# ever read, and install.sh copies all of .local/share into the user's home, so
# every install carries ~20 MB of dead files. They are gone from the repo now.
#
# Only remove the directory if it still holds exactly what we shipped. A user who
# put their own images there keeps everything, including our three files, because
# telling them apart is not worth the risk of deleting someone's wallpaper.

DIR="$HOME/.local/share/wallpapers"
[[ -d $DIR ]] || exit 0

SHIPPED=(lockscreen.png wallpaper.png wallpaper2.jpg)

mapfile -t present < <(cd "$DIR" && find . -mindepth 1 -printf '%P\n' | sort)

expected=$(printf '%s\n' "${SHIPPED[@]}" | sort)
actual=$(printf '%s\n' "${present[@]}")

if [[ $actual == "$expected" ]]; then
  rm -rf "$DIR"
  echo "  Removed $DIR"
else
  echo "  Left $DIR alone: it holds files we did not ship"
fi
