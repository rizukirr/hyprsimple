#!/bin/bash

# Which AUR helper to use. Sourced, never run on its own.
#
# Three callers carried their own copy of this, and all three read yay first:
#
#   if command -v yay &>/dev/null; then AUR_HELPER="yay"
#   elif command -v paru &>/dev/null; then AUR_HELPER="paru"
#
# so a machine set up around paru ran every hyprsimple package operation
# through yay from the moment yay appeared for any other reason, and the
# installer, finding neither, built yay without asking. paru is what CachyOS
# ships and what several other Arch derivatives ship, so preferring yay meant
# preferring the helper the user had not chosen, on the machines most likely to
# have already chosen.
#
# Nothing here installs anything. It reports which helper is present and leaves
# what to do about none of them to the caller, because the three want different
# things: the installer offers to build one, the updater skips AUR packages,
# muslimtify stops.
#
# Both helpers take -S --needed --noconfirm and mean the same thing by it,
# which is why the callers can hold one name and pass the same flags.

# The order only settles a machine that has both. paru first, because a machine
# with both most likely acquired yay as a dependency of something and paru on
# purpose. HYPRSIMPLE_AUR_HELPER overrides it either way.
HYPRSIMPLE_AUR_HELPERS=(paru yay)

# Prints the helper to use.
#
#   0  a helper was found, and its name is on stdout
#   1  no helper is installed
#   2  HYPRSIMPLE_AUR_HELPER names one that is not installed
#
# 2 is separate from 1 on purpose. The installer answers "none installed" by
# building one, and answering an explicit choice that way would install a
# second helper alongside the one the user asked for and never mention it.
aur_helper() {
  local chosen="${HYPRSIMPLE_AUR_HELPER:-}" candidate

  if [[ -n $chosen ]]; then
    if ! command -v "$chosen" >/dev/null 2>&1; then
      echo "hyprsimple: HYPRSIMPLE_AUR_HELPER is set to '$chosen', which is not installed." >&2
      return 2
    fi
    printf '%s\n' "$chosen"
    return 0
  fi

  for candidate in "${HYPRSIMPLE_AUR_HELPERS[@]}"; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

# The flags that stop a helper asking. --noconfirm on its own is not enough:
# paru still opens each PKGBUILD for review and yay still asks about diffs,
# edits and stale build directories, and every one of those waits for a
# keypress. Per helper, because they spell it differently and passing yay's
# flags to paru is an error rather than a no-op.
#
# One flag per line, for `mapfile`. Building a string and splitting it on
# spaces would break the first time a flag needs one.
aur_unattended_flags() {
  case "$1" in
  paru)
    printf '%s\n' --noconfirm --skipreview
    ;;
  yay)
    printf '%s\n' --noconfirm --answerdiff=None --answeredit=None --answerclean=None
    ;;
  *)
    printf '%s\n' --noconfirm
    ;;
  esac
}
