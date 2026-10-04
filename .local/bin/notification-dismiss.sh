#!/bin/bash

# Dismiss every notification on screen. The bar shows them, so it is asked.
exec qs -p "${HYPRSIMPLE_PATH:-$HOME/.local/share/hyprsimple}/default/quickshell" ipc call bar dismissNotifications
