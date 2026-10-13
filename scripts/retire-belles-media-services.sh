#!/bin/bash
# Retire Belles' duplicate media-server roles after a verified Mini cutover.
# Keeps Tailscale, rclone, the external drive, and non-Movies SMB shares.
set -euo pipefail

echo "Stopping and disabling Belles Emby, Caddy, and Movies SMB sharing…"
sudo launchctl bootout system /Library/LaunchDaemons/com.emby.server.plist || true
sudo launchctl disable system/com.emby.server
sudo launchctl bootout system /Library/LaunchDaemons/com.jedison.caddy.plist || true
sudo launchctl disable system/com.jedison.caddy
sudo sharing -r Movies

uid="$(id -u)"
launchctl bootout "gui/$uid" ~/Library/LaunchAgents/com.noside.emby-awake.plist || true
launchctl disable "gui/$uid/com.noside.emby-awake"

echo "Retired: Emby, Caddy, Emby keep-awake, and the Movies SMB share."
echo "Left running: Tailscale, rclone, other SMB shares, and the external drive."
