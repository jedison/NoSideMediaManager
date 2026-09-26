# Backlog

## Next

- Build the explicit local ↔ canonical ↔ consumer mapping review screen, using
  GBBO's UK/Netflix/Emby numbering as the acceptance case.
- Run a copied-one-season GBBO acceptance pilot: scan, map, freeze a portable
  job, dry-run and apply it on the media Mac, normal Emby scan, and verify
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
- Add movie review, NFO, artwork, and move workflows using the same apply and
  manifest model.
- Add TMDB or another provider only as an optional comparison/reference source;
  retain an explicit per-series canonical-order choice.
- Add subtitle-sidecar inspection and language-aware review beyond the current
  portable rename preservation.

## Decisions to make

- Should the app write NFOs beside files, or into a metadata staging folder?
- Which episode order should be the default when TVDB offers more than one?
- Should later providers enrich an existing record or compete as full sources?
