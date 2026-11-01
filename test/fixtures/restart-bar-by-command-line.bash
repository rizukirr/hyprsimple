#!/bin/bash
# A restart script that finds the bar by its command line, the mistake
# test/bar-restart-real-qs-test.sh has to be able to catch. Quickshell gives a
# bar it recovered from a crash a different command line, so this finds nothing.

BAR="$HYPRSIMPLE_PATH/default/quickshell"

bar_running() {
  pgrep -f -- "qs -p $BAR" >/dev/null
}

if [[ ${1:-} == --if-running ]]; then
  bar_running || exit 0
fi

if bar_running; then
  qs kill -p "$BAR" >/dev/null 2>&1
fi

setsid uwsm app -- qs -p "$BAR" >/dev/null 2>&1 &
