# MMM runbook

Repository-side engineering reference for MMM. The authoritative operational
runbook for the old MBA, Emby, media, remote access, and MMM is the Google Doc
[Emby Server Setup Runbook - Old MacBook Air](<private operational document>).
Keep this file aligned with that document, but use the Google Doc for live
operations.

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

### Tailscale

Install Tailscale on the analysis Mac, old MBA, and iPhone, then authenticate
each device into the same Tailnet. The old MBA's current MagicDNS name is:

```text
your-media-server.your-tailnet.ts.net
```

Use that hostname in microMM on the iPhone, rather than a changing home-LAN
address. Check the old MBA's Tailnet reachability from the analysis Mac with:

```zsh
tailscale ping --timeout=10s your-media-server.your-tailnet.ts.net
```

If the name does not resolve on the iPhone, first open Tailscale there and
confirm it is connected to the same Tailnet. A successful Tailscale ping but a
failed Companion connection usually means that `microMM.app` is not yet
allowed in the old MBA's Firewall settings.

### SSH from the analysis Mac to the old MBA

The current key-based connection is:

```zsh
ssh jedison@your-media-server
```

Verify it without allowing a password fallback:

```zsh
ssh -o BatchMode=yes -o ConnectTimeout=12 jedison@your-media-server
```

For a new analysis Mac, first enable **Remote Login** on the old MBA under
**System Preferences → Sharing**. Then add the new Mac's public SSH key to the
old MBA account. From the new Mac, the following sends the default Ed25519
public key and asks for the old MBA account password once:

```zsh
cat ~/.ssh/id_ed25519.pub | ssh jedison@your-media-server 'umask 077; mkdir -p ~/.ssh; cat >> ~/.ssh/authorized_keys'
```

If the new Mac does not yet have that key, create it first:

```zsh
ssh-keygen -t ed25519
```

Never copy a private key between Macs. Test the new key using the password-free
verification command above before relying on it for media work.

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
