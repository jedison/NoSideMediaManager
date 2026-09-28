#!/bin/zsh
# Removes the NoSide Wi-Fi keeper system LaunchDaemon from macOS.

set -euo pipefail

LABEL="com.noside.wifi-keeper"

sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo /bin/rm -f "/Library/LaunchDaemons/$LABEL.plist" /usr/local/libexec/noside-wifi-keeper

print -- "Removed $LABEL. The historical log is retained at /Library/Logs/NoSide/wifi-keeper.log"
