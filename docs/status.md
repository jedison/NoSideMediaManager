# Delivery status — 2026-09-29

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
- Build/test verification: 51 Swift tests pass and the iPhone Release target
  compiles. No package, server configuration, or library content was changed.

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
