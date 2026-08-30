#!/bin/bash

# Mirrors screenrecording_active() in screen-record.sh. waybar re-runs this on
# RTMIN+8, which screen-record.sh already sends on both start and stop.

if pgrep -x wl-screenrec >/dev/null || pgrep -x wf-recorder >/dev/null; then
  echo '{"text": "󰻂", "tooltip": "Recording. Click to stop", "class": "active"}'
else
  echo '{"text": ""}'
fi
