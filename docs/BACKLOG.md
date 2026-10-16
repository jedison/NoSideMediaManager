# Backlog

## Next validation

- Run the real Movie and TV acceptance paths on the current media server:
  review, freeze, dry-run, apply, verify in Emby, and rollback a copied fixture.
- Validate iPhone pairing, shared audit progress, frozen-package actions, and
  result logs against the current Companion server.
- Recheck a GBBO season with intentional duplicate decisions and the official
  UK TVDB order.

## Product work

- Add a visual per-sidecar keep/move/replace review beyond the existing poster
  choice.
- Extend embedded extraction when containers expose cast, crew, genres, studio,
  rating, and description.
- Add a low-resolution movie review filter. Show dimensions or, when they are
  unavailable, file size; offer only intentional keep/review actions.
- Add a suspected-artwork-mismatch review with a human keep/replace decision;
  never overwrite approved or alternate artwork automatically.
- Add season-level TVDB titles, descriptions, dates, and artwork to
  `season.nfo`.
- Add an explicit review workflow for editions, extras, trailers, alternate
  encodes, orphan sidecars, and language-aware subtitle inspection.

## Future platform work

- Document and automate coordinated release, signing, staging, deployment, and
  rollback for macOS and iOS.
- Add CI for the shared tests, macOS/CLI build, and iPhone build.
- Move iPhone pairing secrets to Keychain, then consider QR pairing and Bonjour
  discovery.
- Support explicitly configured additional media roots and job-root mappings.
- Keep any Emby rescan integration opt-in and separate from a package apply.
