# Changelog

This project follows [Semantic Versioning](https://semver.org/).

## 0.2.1 — 2026-09-27

### Added

- Recursive movie audit that separates complete files, extractable embedded
  metadata/artwork, bare files requiring TMDB review, and partial sidecars.
- Embedded-metadata portable job that preserves container title/date/cover art
  as NFO/JPG sidecars without any provider lookup or media-file mutation.

## 0.2.0 — 2026-09-27

### Added

- TMDB-backed movie search, editable movie plans, and canonical `Title (Year)`
  filename normalization.
- Kodi/Emby-compatible `<movie>` NFO generation with TMDB unique IDs, release
  date, plot, runtime, rating, genres, and optional poster artwork.
- Portable movie job bundles with dry-run, apply, rollback, manifest, and
  sidecar/subtitle handling identical to TV jobs.

## 0.1.3 — 2026-09-26

### Changed

- Replaced direct reviewed-library application in the CLI and SwiftUI review
  screen with a frozen portable job-package workflow.
- Added relative-path `apply.sh` and `rollback.sh` scripts with `--dry-run`,
  video/folder moves, generated NFO/artwork replacement, subtitle companion
  moves, and practical job-specific backups.
- Added `manifest.json`, generated sidecars, and target-Mac instructions to
  every job package. The package builder writes only its output folder.

## 0.1.2 — 2026-09-25

### Changed

- Added the GBBO safety rule: a provider's canonical episode order must never
  silently override local filename or Emby identity. Series with differing UK,
  US/Netflix, and scraper orders require an explicit reviewed mapping.
- Selected TVDB's explicit official UK aired order as the default, so GBBO is
  one continuous show with seasons 1–17.
- Added a reviewed rename-plan core which can generate Bash or execute a
  preflighted local move, with a reverse plan for undo.
- Added media-folder scanning, number-for-number mapping proposals, a macOS
  review view, and a conflict-safe episode-artwork downloader.
- Added safe `season.nfo` generation for unambiguous canonical season folders.
- Made reviewed rename plans explicitly support moves to existing destination
  folders, with destination-folder preflight.
- Added a portable, read-only CLI mapping review command for external drives.
- Treat folder-season versus filename-season conflicts as requiring manual
  mapping, preventing false-positive GBBO matches.
- Added companion-aware video moves for NFO and common JPG/PNG sidecars, with
  post-move NFO video-filename reference repair.

## 0.1.1 — 2026-09-25

### Changed

- Lowered the deployment target to macOS Monterey 12 and removed newer URL and
  window-sizing APIs from the initial app.
- Documented XML/NFO as the sole, directly editable metadata store.

## 0.1.0 — 2026-09-25

### Added

- macOS SwiftUI starter interface for TVDB series search and NFO export.
- Provider-neutral series and episode models with a TVDB v4 adapter.
- Local Kodi-compatible `tvshow.nfo` and episode NFO writer.
- Safe import behavior: existing NFO files are preserved by default.
- Swift Testing coverage for XML rendering and atomic preflight behavior.
