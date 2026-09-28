# NoSide Wi-Fi keeper

This system `launchd` daemon sends four ICMP pings to `1.1.1.1` every five
minutes, including once when it is loaded. It records the result at:

`/Library/Logs/NoSide/wifi-keeper.log`

It is intended to keep an idle Wi-Fi connection active and make dropouts
visible. It does not keep a Mac awake or reset a failed Wi-Fi connection. As a
system daemon, it starts before a user logs in. Installing or removing it
requires an administrator password.

Install with `./install.sh`; remove with `./uninstall.sh`.

Installed label: `com.noside.wifi-keeper`.
