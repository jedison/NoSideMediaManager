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
- Add a visual per-sidecar keep/move/replace review to the macOS batch TMDB
  queue. It now supports an editable destination and a per-movie TMDB-poster
  choice; other existing sidecars travel with their video.
- Add optional TMDB backdrop/fanart downloads with explicit Emby/Kodi naming choices and per-item keep/download/replace review.
- Extend embedded movie extraction to cast, crew, genre, studio, rating, and description where a container exposes them.
- Add an ignore-rule editor to the macOS and iPhone UI, backed by the existing
  visible `.noside-mmm-ignore` file and with an audit preview before save.
- Add export/copy controls for structured package-operation history. It is
  already retained as append-only `operation-history.json` beside each job.
- Add saved sort preferences and richer canonical-episode search facets to the
  TV local ↔ canonical ↔ consumer review. It now has safety filters, a text
  episode filter, explicit exclusions, and required duplicate decisions.
- Run a copied-one-season GBBO acceptance pilot: scan, map, freeze a portable
  job, dry-run and apply it on the media server, normal Emby scan, and verify
  rollback before touching the library.
- Add field-by-field NFO merge/acceptance, rather than the current visible
  field-difference review and whole-file generated-NFO replacement.
- Extend package integrity verification to exported ZIP transport and add
  recorded TVDB pagination and malformed-response fixtures. The frozen folder
  now has `SHA256SUMS`/`verify.sh` plus series and official-order fixtures.
- Add a real macOS `.xcodeproj` wrapper for the package when the product moves
  beyond the prototype stage.
- Cache TVDB tokens securely in Keychain, with expiry handling.

## Later

- Enrich `season.nfo` with TVDB season titles, summaries, dates, and artwork.
- Allow named preset collections and source-relative paths in reusable TV
  mapping JSON. The current export/load plan already records explicit
  exclusions transparently and is safe to inspect/edit.
- Add collection/set support and configurable movie-folder layouts.
- Add an explicit keep/ignore/package review workflow for classified editions,
  extras, trailers, featurettes, and alternate encodes. MMM now labels and
  filters them but never acts automatically.
- Add an orphan-sidecar review/package workflow. MMM now reports genuine
  orphans without mistaking language-tagged subtitles for them, and deliberately
  does not delete or move unassociated files.
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
