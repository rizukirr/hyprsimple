echo "Install the Intel video decode drivers, so video is decoded on the GPU"

# install.sh set up a browser and ffmpeg and no VA-API driver for Intel, so on
# an Intel laptop, and on a hybrid one whose desktop runs on the integrated
# GPU, video was decoded on the CPU. install.sh installs the drivers now. This
# is the same thing for a machine that was installed before it did.
#
# Both drivers, because libva tries intel-media-driver first and falls back to
# libva-intel-driver on a GPU too old for it, so nothing here has to tell the
# two apart. Both are in the official repositories.
#
# Only what is missing is asked for, and a machine with no Intel GPU is left
# alone.

command -v lspci >/dev/null 2>&1 || exit 0
lspci | grep -qiE '(VGA|Display).*Intel' || exit 0

missing=()
for pkg in intel-media-driver libva-intel-driver; do
  pacman -Qq "$pkg" &>/dev/null || missing+=("$pkg")
done

if (( ${#missing[@]} == 0 )); then
  exit 0
fi

sudo pacman -S --needed --noconfirm "${missing[@]}" || exit 1

echo "  Installed ${missing[*]}"
echo "  Restart your browser so it can use the driver."
