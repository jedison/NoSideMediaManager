#!/bin/zsh
# Installs the NoSide Wi-Fi keeper as a system LaunchDaemon on macOS.

set -euo pipefail

PACKAGE_DIRECTORY="${0:A:h}"
LABEL="com.noside.wifi-keeper"
DAEMON_PATH="/Library/LaunchDaemons/$LABEL.plist"
EXECUTABLE_PATH="/usr/local/libexec/noside-wifi-keeper"

sudo /usr/bin/install -d -o root -g wheel -m 755 /usr/local/libexec
sudo /usr/bin/install -d -o root -g wheel -m 755 /Library/Logs/NoSide
sudo /usr/bin/install -o root -g wheel -m 755 "$PACKAGE_DIRECTORY/wifi-keeper.sh" "$EXECUTABLE_PATH"
sudo /usr/bin/install -o root -g wheel -m 644 "$PACKAGE_DIRECTORY/$LABEL.daemon.plist" "$DAEMON_PATH"

sudo launchctl bootout "system/$LABEL" 2>/dev/null || true
sudo launchctl bootstrap system "$DAEMON_PATH"
sudo launchctl kickstart -k "system/$LABEL"

print -- "Installed $LABEL. Log: /Library/Logs/NoSide/wifi-keeper.log"
