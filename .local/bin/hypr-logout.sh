#!/bin/bash

# Gracefully log out of the Hyprland/UWSM session.
# Closes all windows first so apps like Chrome shut down cleanly,
# then stops the UWSM session.
#
# That is what the comment always said. What the code did was schedule
#
#   nohup bash -c "sleep 2 && uwsm stop" &
#
# before sending a single close, so the session was torn down two seconds after
# the script started whatever else had happened. closewindow returns as soon as
# the request is sent, and an application decides for itself how long it needs
# afterwards, so two seconds was a guess about every program at once. A browser
# still flushing its profile when the timer fired was killed, which is the one
# thing this script exists to prevent.
#
# It now sends the closes and then waits for the windows to actually go,
# checking rather than assuming, and stops the session as soon as they have.
# The wait is bounded: an application holding an unsaved-changes dialog open
# must not keep someone logged in forever.

CLOSE_TIMEOUT_MS="${HYPRSIMPLE_LOGOUT_TIMEOUT_MS:-8000}"
POLL_MS=100

# Prints how many windows are open, or "unknown" when Hyprland's IPC does not
# answer.
#
# This used to end `| jq 'length' 2>/dev/null || echo 0`. That fallback could
# never run. A pipeline's exit status is its last command's, and jq handed an
# empty stream prints nothing and exits 0, so with hyprctl unavailable the
# count came back empty rather than 0. `[[ "" == 0 ]]` is false, so a logout
# with no reachable IPC waited out the whole timeout and then announced windows
# that had not closed, on a session that had none open.
window_count() {
  local count
  count=$(hyprctl clients -j 2>/dev/null | jq 'length' 2>/dev/null)
  if [[ $count =~ ^[0-9]+$ ]]; then
    printf '%s' "$count"
  else
    printf 'unknown'
  fi
}

hyprctl clients -j 2>/dev/null | jq -r '.[].address' 2>/dev/null | while read -r addr; do
  [[ -n $addr ]] || continue
  hyprctl dispatch closewindow "address:$addr" >/dev/null 2>&1
done

waited=0
while (( waited < CLOSE_TIMEOUT_MS )); do
  count=$(window_count)
  # Nothing left to wait for, or no way to find out. Waiting on a question that
  # cannot be answered just delays the logout by the length of the timeout.
  [[ $count == 0 || $count == unknown ]] && break
  sleep "0.$(printf '%03d' "$POLL_MS")"
  waited=$((waited + POLL_MS))
done

remaining=$(window_count)
if [[ $remaining != 0 && $remaining != unknown ]]; then
  # Said out loud rather than silently waiting the full timeout again: this is
  # the case where something did not close and is about to be stopped anyway.
  # Not said when the count is unknown, which reports on windows nobody counted.
  notify-send "Logging out" "Some windows did not close in time" -t 2000 2>/dev/null
fi

uwsm stop
