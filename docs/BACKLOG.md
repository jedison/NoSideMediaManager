# Backlog

## Next validation

- Run the real Movie and TV acceptance paths on the current media server:
  review, freeze, dry-run, apply, verify in Emby, and rollback a copied fixture.
- Validate iPhone pairing, shared audit progress, frozen-package actions, and
  result logs against the current Companion server.
- Recheck a GBBO season with intentional duplicate decisions and the official
  UK TVDB order.

## Product work

- Extend container extraction when a source exposes reliable cast, crew, and
  rating fields. MMM already retains title, date, description, genres, studio,
  artist/creator, and embedded artwork when present.
- Improve the artwork-comparison review from a local byte-difference candidate
  to an optional provider-artwork visual comparison. Never replace artwork
  automatically.
- Add explicit package actions for reviewed editions/extras and orphan
  sidecars. They are currently surfaced for review, can be revealed/ignored
  where safe, and are never silently moved or deleted.

## Future platform work

- Document and automate coordinated release, signing, staging, deployment, and
  rollback for macOS and iOS.
- Keep the GitHub Actions verification workflow current with Xcode/iOS SDK
  changes and add artifact/signing validation only when a distribution path is
  chosen.
- Move iPhone pairing secrets to Keychain, then consider QR pairing and Bonjour
  discovery.
- Support explicitly configured additional media roots and job-root mappings.
- Keep any Emby rescan integration opt-in and separate from a package apply.
