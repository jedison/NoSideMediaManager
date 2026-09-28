# MMM runbook

Operational notes for the analysis Mac, the old MBA media Mac, and the iPhone
companion.

## Frozen media jobs

1. Generate and review the job on the analysis Mac. MMM does not modify the
   media library there.
2. Copy the complete job folder or ZIP to the old MBA.
3. On the old MBA, dry-run it against the intended show or movie root:

   ```zsh
   ./apply.sh --dry-run "/path/to/media-root"
   ```

4. Inspect the output, then apply with the same media-root argument:

   ```zsh
   ./apply.sh "/path/to/media-root"
   ```

5. Retain `.noside-mmm-backups/<job-id>` until Emby has been checked. Use the
   job's `rollback.sh` if a practical rollback is required.

## Companion connectivity

The MMM Companion server runs in the microMM macOS app on the old MBA. The
iPhone needs Tailscale installed and connected to the same Tailnet in order to
use the old MBA's MagicDNS hostname. Do not expose the Companion port to the
public internet.

The old MBA's Firewall must allow incoming connections for `microMM.app`. If
the iPhone resolves the hostname but cannot connect, confirm that rule before
troubleshooting the Companion itself.

## Old MBA Wi-Fi keeper

The old MBA has a system LaunchDaemon package at:

```text
~/NoSideMediaManagerJobs/wifi-keeper
```

It sends four pings to `1.1.1.1` every five minutes, including at boot, to keep
light traffic on an otherwise idle Wi-Fi link and record connectivity failures.
It does not stop the Mac sleeping or reset a failed Wi-Fi association.

Install it once from Terminal on the old MBA (an administrator password is
required):

```zsh
~/NoSideMediaManagerJobs/wifi-keeper/install.sh
```

Verify recent checks:

```zsh
tail -n 30 /Library/Logs/NoSide/wifi-keeper.log
```

Remove it if no longer wanted:

```zsh
~/NoSideMediaManagerJobs/wifi-keeper/uninstall.sh
```

For an immediate diagnosis when the old MBA appears offline:

```zsh
ping -c 4 1.1.1.1
ping -c 2 apple.com
```

The first command tests the network path without relying on DNS. The second
checks DNS once the first command succeeds.
