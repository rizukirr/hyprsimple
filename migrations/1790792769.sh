echo "Let Hyprland choose the desktop GPU, so every display output works"

# install.sh picked one GPU by vendor, gave it a fixed name under /dev/dri
# with a udev rule, and pointed AQ_DRM_DEVICES at that one device in
# ~/.config/uwsm/env-hyprland. Hyprland then used only that GPU, and a monitor
# on a port wired to the other card had nothing to drive it.
#
# Aquamarine enumerates every GPU itself, starts on the one the firmware
# booted with, and keeps the others for their outputs. Measured on an Intel +
# RTX 4050 laptop with nothing set: it started on the Intel card, held the
# NVIDIA card open for its DisplayPort, and the NVIDIA card still slept for
# 6723 of the first 6885 seconds after boot. CachyOS sets nothing either.
#
# This removes both halves. The block goes from env-hyprland with a backup
# beside it, and the rule goes from the udev directory. The symlink the rule
# made stays until the next boot, and nothing reads it once the export is gone.

ENV_FILE="$HOME/.config/uwsm/env-hyprland"

if [[ -f $ENV_FILE ]] && grep -qE '^(# >>> hyprsimple gpu >>>|export AQ_DRM_DEVICES=)' "$ENV_FILE"; then
  cp -f "$ENV_FILE" "$ENV_FILE.bak"
  # The marked block set_env_block writes, and the unmarked form a run from
  # before the markers existed left: a "# Primary GPU:" comment line and the
  # export after it. Anything else in the file is the user's and stays.
  awk '
    /^# >>> hyprsimple gpu >>>$/ { skip = 1; next }
    /^# <<< hyprsimple gpu <<<$/ { skip = 0; next }
    skip { next }
    /^# Primary GPU: / { next }
    /^export AQ_DRM_DEVICES=/ { next }
    { print }
  ' "$ENV_FILE.bak" >"$ENV_FILE"
  echo "  Removed the AQ_DRM_DEVICES block from $ENV_FILE"
  echo "  Your previous version is at $ENV_FILE.bak"
fi

# The rules directory is the last one install.sh searches, overridable for
# the reason it is overridable there: so a suite never touches /etc.
read -ra rule_dirs <<<"${HYPRSIMPLE_UDEV_RULE_DIRS:-/usr/lib/udev/rules.d /etc/udev/rules.d}"
rules_dir="${rule_dirs[-1]}"
stale=()
for vendor in intel amd nvidia; do
  [[ -e $rules_dir/99-$vendor-gpu.rules ]] && stale+=("$rules_dir/99-$vendor-gpu.rules")
done
if (( ${#stale[@]} > 0 )); then
  sudo rm -f "${stale[@]}" || exit 1
  sudo udevadm control --reload || true
  echo "  Removed ${stale[*]}"
fi

echo "  Hyprland now chooses the desktop GPU itself, and a monitor on a port wired to the other card works from your next login."
