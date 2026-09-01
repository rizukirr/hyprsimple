#!/bin/bash

OUTPUT_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  dunstify "Screen recording directory does not exist: $OUTPUT_DIR" -u critical -t 3000
  exit 1
fi

SCOPE="$1"      # "region", "output", or "stop"
AUDIO_MODE="$2" # "mic", "internal", or "none"

start_screenrecording() {
  local stamp
  stamp=$(date +'%Y-%m-%d_%H-%M-%S')
  local filename="$OUTPUT_DIR/screenrecording-$stamp.mp4"
  local audio_opts=()

  # Detect whether wf-recorder or wl-screenrec will be used
  local is_nvidia=false
  if lspci | grep -qi 'nvidia'; then
    is_nvidia=true
  fi

  # Configure audio source depending on mode
  case "$AUDIO_MODE" in
  mic)
    # Capture from default mic
    audio_opts=(--audio)
    ;;
  internal)
    # Capture from system monitor source
    # Replace below with your actual monitor source name if needed
    MONITOR_SOURCE=$(pw-cli ls Node | grep monitor | head -n 1 | awk '{print $2}')
    if [[ -z "$MONITOR_SOURCE" ]]; then
      dunstify "No monitor source found for internal audio!" -u critical -t 3000
      exit 1
    fi
    audio_opts=(--audio="pw:$MONITOR_SOURCE")
    ;;
  none | "")
    audio_opts=()
    ;;
  *)
    dunstify "Invalid audio mode: $AUDIO_MODE (use mic/internal/none)" -u critical -t 3000
    exit 1
    ;;
  esac

  # Run recorder
  if $is_nvidia; then
    wf-recorder "${audio_opts[@]}" -f "$filename" \
      -c libx264 -p crf=23 -p preset=medium -p movflags=+faststart "$@" &
  else
    wl-screenrec "${audio_opts[@]}" -f "$filename" \
      --ffmpeg-encoder-options="-c:v libx264 -crf 23 -preset medium -movflags +faststart" "$@" &
  fi

  toggle_screenrecording_indicator
}

stop_screenrecording() {
  pkill -x wl-screenrec
  pkill -x wf-recorder
  dunstify "Screen recording saved to $OUTPUT_DIR" -t 2000
  sleep 0.2
  toggle_screenrecording_indicator
}

toggle_screenrecording_indicator() {
  pkill -RTMIN+8 waybar
}

screenrecording_active() {
  pgrep -x wl-screenrec >/dev/null || pgrep -x wf-recorder >/dev/null
}

if [[ "$SCOPE" == "stop" ]]; then
  # Stop-only. The waybar indicator clicks this, and without it a click while
  # nothing is recording would fall through to the region branch and pop up a
  # selector.
  screenrecording_active && stop_screenrecording
  exit 0
fi

if screenrecording_active; then
  stop_screenrecording
elif [[ "$SCOPE" == "output" ]]; then
  output=$(slurp -o) || exit 1
  start_screenrecording -g "$output"
else
  region=$(slurp) || exit 1
  start_screenrecording -g "$region"
fi
