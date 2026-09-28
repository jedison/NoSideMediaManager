# MMM Companion architecture

## Phase 1 — delivered

The original macOS MMM SwiftUI app has a **Companion** tab. It starts/stops an
authenticated local server and owns its jobs root, one selected library root,
port, and pairing token. It never exposes SMB or general filesystem operations.

The native iOS app lives in `Companion iOS/`. It pairs using the old MBA's LAN
address, port, and token, lists frozen jobs, displays operation logs, and can
request dry-run, apply, or rollback. Apply requires both the bearer token and a
second request header containing the exact job ID.

Only these server routes exist:

- `GET /v1/health`
- `GET /v1/jobs`
- `POST /v1/jobs/<job-id>/dry-run`
- `POST /v1/jobs/<job-id>/apply`
- `POST /v1/jobs/<job-id>/rollback`

The server resolves job IDs from `manifest.json` files below its configured jobs
directory. It does not accept filesystem paths from the phone.

## Phase 2 — after first paired-device pilot

- Secure the iOS token in Keychain rather than UserDefaults.
- Add QR pairing and Bonjour discovery instead of manual address entry.
- Support an allowed list of media roots per job, rather than the initial one
  selected root.
- Add job history/persisted logs and a server activity view.
- Add certificate-based HTTPS or VPN-only remote access before any use beyond
  the trusted home LAN.

## Deployment boundary

The companion must run in the MMM app on the old MBA while jobs are managed.
The iOS project builds for iOS 16+, but installing it on a real phone requires
the user’s Xcode signing team and connected target device. Do not expose the
Companion port directly to the internet.
