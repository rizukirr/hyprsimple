#!/bin/bash

# Collect everything needed to diagnose a hyprsimple problem into one file, then
# view, save, or upload it.
#
#   hyprsimple-debug.sh              # interactive
#   hyprsimple-debug.sh --print      # dump to stdout
#   hyprsimple-debug.sh --upload     # straight to 0x0.st
#   hyprsimple-debug.sh --no-sudo    # skip dmesg (avoids the password prompt)
#
# Attach the resulting link when opening an issue.

export HYPRSIMPLE_PATH="${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}"

LOG_FILE="/tmp/hyprsimple-debug.log"
INSTALL_LOG="$HOME/.local/state/hyprsimple/install.log"

PRINT_ONLY=false
UPLOAD_ONLY=false
NO_SUDO=false

while (( $# > 0 )); do
  case "$1" in
    --print)   PRINT_ONLY=true ;;
    --upload)  UPLOAD_ONLY=true ;;
    --no-sudo) NO_SUDO=true ;;
    -h|--help)
      sed -n '3,12p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
  shift
done

# Print a section only if the tool backing it exists, so this works on a
# minimal install without erroring out.
section() {
  echo ""
  echo "========================================="
  echo "$1"
  echo "========================================="
}

hyprsimple_version() {
  local version branch
  version=$(cat "$HYPRSIMPLE_PATH/version" 2>/dev/null || echo "unknown")
  branch=$(git -C "$HYPRSIMPLE_PATH" branch --show-current 2>/dev/null || echo "unknown")
  echo "Version:   $version"
  echo "Branch:    $branch"
  echo "Commit:    $(git -C "$HYPRSIMPLE_PATH" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  echo "Path:      $HYPRSIMPLE_PATH"
}

{
  section "HYPRSIMPLE"
  echo "Date:      $(date)"
  echo "Hostname:  $(hostname)"
  echo "Kernel:    $(uname -r)"
  hyprsimple_version

  section "MIGRATIONS"
  state_dir="$HOME/.local/state/hyprsimple/migrations"
  if [[ -d $state_dir ]]; then
    echo "Applied:"
    find "$state_dir" -maxdepth 1 -type f -printf '  %f\n' 2>/dev/null | sort || echo "  (none)"
    echo "Skipped after failure:"
    find "$state_dir/skipped" -maxdepth 1 -type f -printf '  %f\n' 2>/dev/null | sort || echo "  (none)"
    echo "Pending:"
    for m in "$HYPRSIMPLE_PATH/migrations"/*.sh; do
      [[ -f $m ]] || continue
      name=$(basename "$m")
      [[ -f "$state_dir/$name" || -f "$state_dir/skipped/$name" ]] || echo "  $name"
    done
  else
    echo "(no migration state - this install predates the migration system)"
  fi

  section "SYSTEM"
  if command -v inxi >/dev/null 2>&1; then
    inxi -Farz -c0 2>/dev/null
  elif command -v fastfetch >/dev/null 2>&1; then
    fastfetch --logo none --pipe 2>/dev/null
  else
    echo "(neither inxi nor fastfetch installed)"
    echo "CPU:  $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | xargs)"
    echo "GPU:  $(lspci | grep -iE 'vga|3d|display' | cut -d: -f3- | xargs)"
    echo "Mem:  $(free -h | awk '/^Mem:/ {print $2 " total, " $3 " used"}')"
  fi

  section "HYPRLAND"
  if command -v hyprctl >/dev/null 2>&1 && [[ -n ${HYPRLAND_INSTANCE_SIGNATURE:-} ]]; then
    hyprctl version 2>/dev/null
    echo ""
    echo "--- monitors ---"
    hyprctl monitors 2>/dev/null
  else
    echo "(Hyprland not running, or hyprctl unavailable)"
    pacman -Qi hyprland 2>/dev/null | grep -E '^(Name|Version)' || true
  fi

  section "JOURNAL (this boot, warnings and errors)"
  journalctl -b -p 4..1 --no-pager 2>/dev/null | tail -n 300 || echo "(unavailable)"

  section "DMESG"
  if [[ $NO_SUDO == "true" ]]; then
    echo "(skipped - --no-sudo)"
  else
    sudo dmesg 2>/dev/null | tail -n 200 || echo "(unavailable)"
  fi

  section "HYPRSIMPLE INSTALL LOG"
  if [[ -f $INSTALL_LOG ]]; then
    tail -n 400 "$INSTALL_LOG"
  else
    echo "(no install log at $INSTALL_LOG)"
  fi

  section "EXPLICITLY INSTALLED PACKAGES"
  if command -v expac >/dev/null 2>&1; then
    # shellcheck disable=SC2046  # splitting is wanted: one argument per package
    expac -Q '%n %v' $(pacman -Qqe) 2>/dev/null | sort
  else
    pacman -Qe 2>/dev/null || echo "(unavailable)"
  fi
} >"$LOG_FILE" 2>&1

upload() {
  echo "Uploading to 0x0.st..."
  local url
  url=$(curl -sF "file=@$LOG_FILE" -Fexpires=24 https://0x0.st)

  if [[ -n $url ]]; then
    echo ""
    echo "Log uploaded. Share this link on your issue:"
    echo ""
    echo "  $url"
    echo ""
    echo "It expires in 24 hours."
  else
    echo "Upload failed. The log is still at $LOG_FILE" >&2
    return 1
  fi
}

if [[ $PRINT_ONLY == "true" ]]; then
  cat "$LOG_FILE"
  exit 0
fi

if [[ $UPLOAD_ONLY == "true" ]]; then
  upload
  exit $?
fi

echo "Collected $(wc -l <"$LOG_FILE") lines into $LOG_FILE"
echo ""
echo "This contains your hostname, kernel, hardware, journal warnings and"
echo "package list. Review it before uploading if that concerns you."
echo ""

options=("View log" "Save to current directory" "Quit")
if ping -c 1 -W 2 1.1.1.1 >/dev/null 2>&1; then
  options=("Upload log" "${options[@]}")
fi

PS3="Choose: "
select choice in "${options[@]}"; do
  case "$choice" in
    "Upload log")                upload; break ;;
    "View log")                  ${PAGER:-less} "$LOG_FILE" ;;
    "Save to current directory") cp "$LOG_FILE" ./hyprsimple-debug.log
                                 echo "Saved to $(pwd)/hyprsimple-debug.log"; break ;;
    "Quit"|"")                   break ;;
    *)                           echo "Invalid choice" ;;
  esac
done
