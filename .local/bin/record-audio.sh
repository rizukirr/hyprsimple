#!/bin/bash

# Record audio from the default input into ~/Music.
#
# install.sh creates ~/Videos and ~/Pictures and not ~/Music, and ffmpeg does
# not create the directory it is asked to write into, so on a machine where
# xdg-user-dirs has not run this exited 254 with "No such file or directory"
# and nothing else. Its two siblings both handle this: screen-record.sh checks
# and says so, and screenshot.sh delegates to hyprshot, which does mkdir -p.
# This one did neither.
OUTPUT_DIR="${XDG_MUSIC_DIR:-$HOME/Music}"
mkdir -p "$OUTPUT_DIR" || exit 1

ffmpeg -f alsa -i default "$OUTPUT_DIR/$(date +%Y%m%d_%H%M%S).wav"
