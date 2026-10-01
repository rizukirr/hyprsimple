echo "Install the Intel video decode drivers, so video is decoded on the GPU"

# install.sh set up a browser and ffmpeg and no VA-API driver for Intel, so on
# an Intel laptop, and on a hybrid one whose desktop runs on the integrated
# GPU, video was decoded on the CPU. install.sh installs the driver now. This
# is the same thing for a machine that was installed before it did.
#
# One driver, intel-media-driver, which covers Broadwell (2014) and newer. An
# Intel GPU older than that keeps decoding on the CPU: telling the generations
# apart takes a list of device IDs, and the decision on 2026-10-01 was to
# leave the list out rather than maintain it.
#
# Only what is missing is asked for, and a machine with no Intel GPU is left
# alone.

command -v lspci >/dev/null 2>&1 || exit 0
lspci | grep -qiE '(VGA|Display).*Intel' || exit 0

pacman -Qq intel-media-driver &>/dev/null && exit 0

sudo pacman -S --needed --noconfirm intel-media-driver || exit 1

echo "  Installed intel-media-driver"
echo "  Restart your browser so it can use the driver."
