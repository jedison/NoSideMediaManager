#!/bin/zsh
# Keep a small amount of traffic flowing so an idle Wi-Fi link is easier to
# spot. This does not prevent macOS from sleeping or wake a sleeping Mac.

set -u

LOG_DIRECTORY="/Library/Logs/NoSide"
LOG_FILE="$LOG_DIRECTORY/wifi-keeper.log"

mkdir -p "$LOG_DIRECTORY"

{
  print -- "$(date '+%Y-%m-%d %H:%M:%S %Z')  checking 1.1.1.1 (4 pings)"
  /sbin/ping -c 4 -W 1000 1.1.1.1
  status=$?
  if [[ $status -eq 0 ]]; then
    print -- "$(date '+%Y-%m-%d %H:%M:%S %Z')  Wi-Fi/internet reachable"
  else
    print -- "$(date '+%Y-%m-%d %H:%M:%S %Z')  Wi-Fi/internet check failed (exit $status)"
  fi
  print
} >> "$LOG_FILE" 2>&1

exit $status
