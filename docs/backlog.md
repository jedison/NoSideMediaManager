# Backlog

## Next

- Deploy and smoke-test the local-only shared-TV-audit/ignore-rules release
  when the media server and iPhone deployment window reopens. Verify that a
  macOS request and iPhone request for the same show attach to one server audit.
- Pair the iOS Companion with the media server using a real frozen job and validate
  dry-run, explicit apply, rollback, and log display before broader use.
- Move the iOS pairing token from UserDefaults to Keychain; add QR pairing and
  Bonjour discovery after the first network pilot.
- Add allowed multiple media roots/job-root mapping to the Companion server.
- Add editable per-item destination and sidecar choices to the macOS batch
  TMDB review queue; it currently creates the standard normalized layout.
- Add optional TMDB backdrop/fanart downloads with explicit Emby/Kodi naming choices and per-item keep/download/replace review.
- Extend embedded movie extraction to cast, crew, genre, studio, rating, and description where a container exposes them.
- Add an ignore-rule editor to the macOS and iPhone UI, backed by the existing
  visible `.noside-mmm-ignore` file and with an audit preview before save.
- Retain structured dry-run/apply/rollback history in each package rather than
  only showing the most recent operation result in the UI.
- Build the explicit local ↔ canonical ↔ consumer mapping review screen, using
  GBBO's UK/Netflix/Emby numbering as the acceptance case.
- Run a copied-one-season GBBO acceptance pilot: scan, map, freeze a portable
  job, dry-run and apply it on the media server, normal Emby scan, and verify
  rollback before touching the library.
- Add field-by-field NFO acceptance, rather than the current whole-file
  replacement choice.
- Add visual episode-artwork review with keep / download / replace per file.
- Add a visual job-package preview (including generated artwork) before export.
- Add an optional ZIP action using macOS `ditto`, while keeping the portable
  folder as the inspected source package.
- Add recorded TVDB response fixtures for series, official episode order,
  artwork URLs, pagination, and malformed API responses.
- Add a real macOS `.xcodeproj` wrapper for the package when the product moves
  beyond the prototype stage.
- Cache TVDB tokens securely in Keychain, with expiry handling.

## Later

- Enrich `season.nfo` with TVDB season titles, summaries, dates, and artwork.
- Save reusable mapping presets as transparent JSON beside a library (never as
  authoritative media metadata), for recurring regional/streaming orders.
- Add collection/set support and configurable movie-folder layouts.
- Add explicit handling for editions, extras, trailers, featurettes, and
  alternate encodes rather than only flagging their likely filename hints.
- Add TMDB or another provider only as an optional comparison/reference source;
  retain an explicit per-series canonical-order choice.
- Add subtitle-sidecar inspection and language-aware review beyond the current
  portable rename preservation.
- Add optional Emby library rescan guidance/launch integration after a package
  applies; keep it opt-in and never couple it to a mutation.

## Decisions to make

- Should the app write NFOs beside files, or into a metadata staging folder?
- Which episode order should be the default when TVDB offers more than one?
- Should later providers enrich an existing record or compete as full sources?
