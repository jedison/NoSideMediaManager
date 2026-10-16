# Delivery status — 2026-09-29

## Pre-validation hardening — 2026-10-12

- Movie audits now label likely trailers, featurettes, behind-the-scenes clips,
  commentaries, alternate encodes, and editions. The explicit-review categories
  have their own macOS filter; the label is advisory and never changes a file.
- Language-suffixed subtitle sidecars such as `Film.en.forced.srt` are no
  longer misreported as orphaned merely because they do not exactly share the
  video stem.
- Every newly frozen package contains `SHA256SUMS` and `verify.sh`. `apply.sh`
  verifies all frozen scripts, manifest, README, and generated files before a
  dry-run or real apply can proceed.
- Recorded offline fixtures now exercise TVDB login, series detail, and the
  GBBO-style official episode order. The suite has 60 passing Swift tests and
  the macOS executable builds successfully.
- `scripts/migrate-mmm-state-to-media-server.sh` supports a reviewable,
  destination-side migration of frozen jobs and MMM preferences to a replacement
  media server. It intentionally excludes app bundles, media files, disks, and
  Keychain secrets.
- After a replacement-server validation, the prior server's duplicate Emby,
  Caddy, Emby keep-awake, and Movies SMB services were retired.
  `scripts/retire-old-media-server-services.sh`
  preserves the reversible launch configuration while leaving Tailscale,
  rclone, other shares, and the media volume untouched.

## Local-only release candidate — 2026-10-01

The following is built and verified locally, but deliberately not deployed
while the media server/iPhone deployment window is unavailable:

- TV folder audits are now shared Companion work. Starting the same show from
  macOS or iPhone joins its in-flight audit rather than scanning it twice.
  The last completed per-show result is retained by the Companion in the Jobs
  folder and is surfaced when the folder is selected again.
- The iPhone TV flow now shows the selected folder's active audit state and
  last-completed time, alongside duplicate-episode candidates.
- Movie-library ignore rules have a safe CLI workflow:
  `movie-ignore-list` and `movie-ignore-add`. Rules remain visible,
  line-oriented `.noside-mmm-ignore` configuration at the library root;
  traversal and hidden-file rules are rejected.
- Companion-initiated dry-run, apply, and rollback operations are retained as
  append-only `operation-history.json` records beside each frozen package and
  shown in the iPhone package detail view after reconnecting.
- macOS Movie Manager now provides a batch explicit-TMDB review route: select
  one or more `bareNeedsTMDB` movies, search and choose the correct TMDB
  result for each, then freeze one folder-normalising package. It writes the
  standard locked NFO and poster where available, but never applies the
  package or changes a movie from the search view.
- Within that batch review, each chosen movie exposes its proposed full
  destination path and a separate TMDB poster download/replace switch before
  it is frozen. Existing local sidecars remain move-preserved.
- Package Operations now has text/state filters, explicit ready/applied/
  rolled-back labels, unavailable-artwork warnings, retained operation logs,
  safe reveal action, and optional `ditto` ZIP export for a selected frozen
  package. The folder remains the authoritative reviewed package.
- macOS also exposes the current `.noside-mmm-ignore` rules and an explicit
  add-rule control. The configuration remains a human-editable text file.
- Movie health can be exported as a standalone HTML report from macOS or with
  `movie-health-html`; JSON remains available for automation.
- macOS Movie audit now makes the health findings actionable with filters for
  all attention items, invalid NFO XML, and every video sharing a duplicate
  TMDB ID. Those details persist in a shared-audit result as well.
- TV audit now reports the filename and byte size for every local duplicate
  candidate. Before a TV package can freeze, each discovered video must be
  mapped or explicitly excluded; each duplicate episode group requires exactly
  one user-selected kept file. Exclusions are retained in the frozen manifest
  notes and never delete the excluded source.
- Build/test verification: 51 Swift tests pass and the iPhone Release target
  compiles. No package, server configuration, or library content was changed.

## TV review strengthening — 2026-10-06

- macOS TV mapping review now filters a GBBO-scale set by unresolved decision,
  ready mapping, NFO change, season conflict, or duplicate candidate, and has
  a TVDB episode text filter. Existing NFO differences are shown by field
  before the package is frozen.
- The Mac displays a package preview before selecting an output folder: included
  episodes, moves, generated episode/show/season NFOs, opted-in TVDB JPGs, and
  explicit exclusions. Artwork review makes the keep-existing-JPG/download
  choice visible per episode. No library file is changed by either review.
- Mapping plans can now carry explicit exclusions and remain backward-readable.
  The macOS export/load controls provide a transparent reusable JSON plan for
  repeat regional/streaming mappings; it is still reviewed before freeze.
- Companion TV review now includes canonical episode choices and can request a
  TV frozen package. The server re-scans the selected configured show folder,
  requires one explicit decision per local video, validates TVDB IDs, and
  enforces exactly one kept candidate per duplicate group before writing the
  package. It never accepts an arbitrary library path or performs a mutation.
- Verification: 55 Swift tests, macOS executable build, and iOS Release build
  pass locally. iOS remains deliberately undeployed.

## Shipped

- Integrated macOS MMM Companion server and native iOS companion project;
  both compile locally. See `docs/companion-architecture.md`.
- TVDB television review, canonical episode mapping, NFO/JPG generation, and portable dry-run/apply/rollback jobs.
- TMDB movie lookup and transparent JSON plans. `movie-bundle` accepts a reviewed plan containing multiple movies and freezes one transaction.
- Movie audit (`movie-audit`) that recursively reports complete items, extractable embedded metadata, bare videos needing TMDB review, and partial sidecars.
- Embedded movie packages: an MP4/M4V/MOV container's title, date, and cover art can become NFO/JPG sidecars without provider lookup or a rename.
- Movie health report (`movie-health`): invalid movie NFO XML, duplicate TMDB IDs, missing sidecars, and likely editions/extras are visible in JSON.
- Portable manifests contain relative paths, generated sidecars, rollback instructions, and best-effort size/mtime source fingerprints. The target script rejects changed files when a fingerprint was available at review time.
- A Monterey SwiftUI Movies tab can audit a selected folder and generate an embedded-metadata package for a selected eligible file.
- Complete movies with valid TMDB NFOs can now be exported as an editable
  preservation plan and frozen into a move-only per-movie-folder package.
  Existing XML, posters, fanart, clearlogos, and subtitle sidecars are moved
  byte-for-byte rather than regenerated.
- TVDB movie search is available as a second, read-only candidate source beside TMDB. Provider IDs are never auto-merged.
- Shared multi-part movies named with `CD`, `Disc`, `Disk`, or `Part` numeric
  suffixes now recognise one shared NFO/artwork set and are excluded from
  per-part embedded-sidecar packages.
- macOS and iPhone now present frozen packages for dry-run, confirmed apply,
  rollback, and readable result logs. macOS Companion auto-starts from saved
  settings when microMM opens.
- The iPhone landing screen has direct Movie and TV entry points; frozen jobs
  remain available as a secondary package-history view.

## Operating model

The analysis Mac never mutates the reviewed library. Copy the package to the media server, run `./apply.sh --dry-run "/path/to/library-root"`, inspect the output, then apply. Keep `.noside-mmm-backups/<job-id>` until Emby is verified.

## Deliberate limits

- TMDB/TVDB matching is explicit. MMM will not auto-assign a bare filename to a search result or merge provider IDs because a wrong movie identity is worse than an unresolved one.
- Embedded tags are strongest for MP4/M4V/MOV. A tag-poor MKV is reported as needing TMDB review; it is never guessed.
- Current artwork is a poster JPG. Fanart/backdrops are not yet generated.
- Fingerprints use file size plus modification time by default. `--sha256` is available for locally readable media when a stronger, slower check is wanted.
