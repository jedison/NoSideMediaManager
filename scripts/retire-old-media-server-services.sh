#!/bin/bash
# Retire a replaced media server's duplicate roles after a verified cutover.
# Keeps Tailscale, rclone, the external drive, and non-Movies SMB shares.
set -euo pipefail

echo "Stopping and disabling Emby and Movies SMB sharing…"
sudo launchctl bootout system /Library/LaunchDaemons/com.emby.server.plist || true
sudo launchctl disable system/com.emby.server
# Caddy labels vary by installation. Supply the known label explicitly when
# needed, e.g. MMM_CADDY_LAUNCHD_LABEL=com.example.caddy ./scripts/... .
if [ -n "${MMM_CADDY_LAUNCHD_LABEL:-}" ]; then
  sudo launchctl bootout "system/${MMM_CADDY_LAUNCHD_LABEL}" || true
  sudo launchctl disable "system/${MMM_CADDY_LAUNCHD_LABEL}" || true
fi
sudo sharing -r Movies

uid="$(id -u)"
launchctl bootout "gui/$uid" ~/Library/LaunchAgents/com.noside.emby-awake.plist || true
launchctl disable "gui/$uid/com.noside.emby-awake"

echo "Retired: Emby, optional Caddy, Emby keep-awake, and the Movies SMB share."
echo "Left running: Tailscale, rclone, other SMB shares, and the external drive."
