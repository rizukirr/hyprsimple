#!/bin/bash

OUTPUT_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}"

if [[ ! -d "$OUTPUT_DIR" ]]; then
  notify-send "Screen recording directory does not exist: $OUTPUT_DIR" -u critical -t 3000
  exit 1
fi

SCOPE="$1"      # "region", "output", or "stop"
AUDIO_MODE="$2" # "mic", "internal", or "none"

# The monitor of the default sink, which is what "system audio" means here.
#
# This was `pw-cli ls Node | grep monitor | awk '{print $2}'`. A monitor is a
# port in pipewire rather than a node, so `pw-cli ls Node` never prints the word
# at all: measured on a working desktop, zero matching lines. Both System Audio
# keybinds therefore died on "No monitor source found" on every machine, which
# is every install this feature has ever had.
#
# The name is checked against the source list rather than assumed, so a sink
# with no monitor is reported instead of being handed to the recorder.
default_monitor_source() {
  local sink monitor
  sink=$(pactl get-default-sink 2>/dev/null) || return 0
  [[ -n $sink ]] || return 0
  monitor="$sink.monitor"
  pactl list short sources 2>/dev/null | cut -f2 | grep -qxF "$monitor" || return 0
  printf '%s' "$monitor"
}

start_screenrecording() {
  local stamp
  stamp=$(date +'%Y-%m-%d_%H-%M-%S')
  local filename="$OUTPUT_DIR/screenrecording-$stamp.mp4"
  local audio_opts=()

  # Which recorder runs has to be settled before the audio flags are built,
  # because the two do not take the same ones.
  local recorder=wl-screenrec
  if "$HOME/.local/bin/hyprsimple-hw-nvidia.sh"; then
    recorder=wf-recorder
  fi

  # Configure audio source depending on mode
  case "$AUDIO_MODE" in
  mic)
    # Capture from default mic. Both recorders spell this the same way.
    audio_opts=(--audio)
    ;;
  internal)
    local monitor
    monitor=$(default_monitor_source)
    if [[ -z "$monitor" ]]; then
      notify-send "No monitor source found for internal audio!" -u critical -t 3000
      exit 1
    fi
    # One device name, two spellings. wf-recorder takes it as the value of
    # --audio. wl-screenrec's --audio is a flag that takes no value at all, and
    # rejects the command outright if given one, so the device goes to its own
    # option. The old form passed wf-recorder's spelling to both.
    if [[ $recorder == wf-recorder ]]; then
      audio_opts=(--audio="$monitor")
    else
      audio_opts=(--audio --audio-device "$monitor")
    fi
    ;;
  none | "")
    audio_opts=()
    ;;
  *)
    notify-send "Invalid audio mode: $AUDIO_MODE (use mic/internal/none)" -u critical -t 3000
    exit 1
    ;;
  esac

  # Run recorder
  if [[ $recorder == wf-recorder ]]; then
    wf-recorder "${audio_opts[@]}" -f "$filename" \
      -c libx264 -p crf=23 -p preset=medium -p movflags=+faststart "$@" &
  else
    wl-screenrec "${audio_opts[@]}" -f "$filename" \
      --ffmpeg-encoder-options="-c:v libx264 -crf 23 -preset medium -movflags +faststart" "$@" &
  fi
  local pid=$!

  # The recorder is backgrounded, so a bad argument or a missing shared library
  # ends it immediately and silently: no file, no indicator, no message. Give it
  # a moment and say so if it is already gone.
  sleep 0.4
  if ! kill -0 "$pid" 2>/dev/null; then
    notify-send "Screen recording failed to start ($recorder)" -u critical -t 5000
    exit 1
  fi

  toggle_screenrecording_indicator
}

stop_screenrecording() {
  pkill -x wl-screenrec
  pkill -x wf-recorder
  notify-send "Screen recording saved to $OUTPUT_DIR" -t 2000
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
