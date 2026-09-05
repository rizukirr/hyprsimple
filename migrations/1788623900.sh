echo "Stop forcing every OpenGL application onto the discrete GPU"

# install.sh appended a block to ~/.config/uwsm/env whenever it found an NVIDIA
# GPU, without asking whether that GPU drives the desktop:
#
#   # NVIDIA (Turing+ with GSP firmware) - auto-detected by installer
#   export NVD_BACKEND=direct
#   export LIBVA_DRIVER_NAME=nvidia
#   export __GLX_VENDOR_LIBRARY_NAME=nvidia
#
# On a hybrid laptop it does not. detect_and_setup_multi_gpu prefers the
# integrated GPU and points AQ_DRM_DEVICES at it, so Hyprland renders on Intel
# or AMD while those variables send every OpenGL application to the discrete
# card. The frames are then copied back to the GPU that owns the display, and
# the dGPU cannot power down. Measured on an Optimus laptop: with the block,
# glxinfo reported the RTX 4050; without it, the Intel iGPU.
#
# Removed only on a machine that has an integrated GPU. A desktop whose only
# card is NVIDIA needs these and keeps them. prime-run still puts a single
# program on the discrete card.

ENV_FILE="$HOME/.config/uwsm/env"

[[ -f $ENV_FILE ]] || exit 0
grep -q '^export __GLX_VENDOR_LIBRARY_NAME=nvidia$' "$ENV_FILE" || exit 0

command -v lspci >/dev/null 2>&1 || exit 0
other_gpu=$(lspci -D | grep -iE "VGA.*Intel" | head -1 | cut -d' ' -f1)
[[ -n $other_gpu ]] ||
  other_gpu=$(lspci -D -d ::0300 | grep -i "AMD" | head -1 | cut -d' ' -f1)

if [[ -z $other_gpu ]]; then
  echo "  This machine has no integrated GPU, so the NVIDIA variables are correct here and are being kept."
  exit 0
fi

cp -f "$ENV_FILE" "$ENV_FILE.bak"

# Only the block install.sh wrote: its comment line, and the exports that
# follow it. A hand-written export elsewhere in the file is left alone.
awk '
  /^# NVIDIA \(.*\) - auto-detected by installer$/ { skip = 1; next }
  skip && /^export (NVD_BACKEND|LIBVA_DRIVER_NAME|__GLX_VENDOR_LIBRARY_NAME)=/ { next }
  skip { skip = 0 }
  { print }
' "$ENV_FILE.bak" >"$ENV_FILE"

echo "  Removed the NVIDIA environment block from $ENV_FILE"
echo "  Your previous version is at $ENV_FILE.bak"
echo "  The desktop renders on the integrated GPU at $other_gpu, which is what AQ_DRM_DEVICES already says."
echo "  Run one program on the NVIDIA GPU with: prime-run <program>"
echo "  This takes effect at your next login."
