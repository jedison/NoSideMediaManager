# Project status

Updated 2026-10-16.

## Current structure

MMM is one NoSide project with a single Xcode project:

- `microMM`: the macOS application and Companion server.
- `noside-media`: the matching embedded command-line tool.
- `microMMCompanion`: the iPhone companion.
- `NoSideMediaManager` and `NoSideMediaCompanionCore`: shared macOS code.

`project.yml` is the tracked XcodeGen definition; regenerate the project with
`xcodegen generate` after changing it. `Package.swift` remains for lightweight
Swift Package command-line and test use while the Xcode project is the place to
open and manage all MMM targets together.

## Delivered

- TVDB official-order TV review, including explicit mappings, duplicate
  decisions, editable reusable plans, locked XML/NFO sidecars, season/show
  NFOs, and optional poster JPGs.
- TMDB movie review, embedded metadata extraction, move-only sidecar
  preservation, movie-folder normalisation, multi-part handling, and audit
  exclusions.
- Frozen packages only: generated `apply.sh`, `rollback.sh`, manifest,
  integrity verification, source fingerprints, and operation history.
- macOS and iPhone review flows, with the Companion limited to authenticated
  audits, provider searches, package creation, dry-run, apply, rollback, and
  logs. It is not a file server.
- Locked NFOs (`<lockdata>true</lockdata>`) so Emby retains reviewed metadata.

## Validation

The current source passes 65 shared tests through both Swift Package Manager
and the `microMM` Xcode scheme. The macOS app/CLI and the iPhone companion also
build from `NoSideMediaManager.xcodeproj`.

## Operational boundary

MMM never mutates a media library during an audit or review. A reviewed,
portable package is dry-run and applied on the media server; the package retains
rollback evidence until Emby has been checked. See [the runbook](runbook.md).

## Next human validation

Run one real movie and one real TV package end-to-end on the current media
server: review, freeze, dry-run, apply, confirm in Emby, then confirm rollback
on a copied fixture. The remaining engineering work is maintained in the
[backlog](BACKLOG.md).
