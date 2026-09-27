# Delivery status — 2026-09-27

## Shipped

- TVDB television review, canonical episode mapping, NFO/JPG generation, and portable dry-run/apply/rollback jobs.
- TMDB movie lookup and transparent JSON plans. `movie-bundle` accepts a reviewed plan containing multiple movies and freezes one transaction.
- Movie audit (`movie-audit`) that recursively reports complete items, extractable embedded metadata, bare videos needing TMDB review, and partial sidecars.
- Embedded movie packages: an MP4/M4V/MOV container's title, date, and cover art can become NFO/JPG sidecars without provider lookup or a rename.
- Movie health report (`movie-health`): invalid movie NFO XML, duplicate TMDB IDs, missing sidecars, and likely editions/extras are visible in JSON.
- Portable manifests contain relative paths, generated sidecars, rollback instructions, and best-effort size/mtime source fingerprints. The target script rejects changed files when a fingerprint was available at review time.
- A Monterey SwiftUI Movies tab can audit a selected folder and generate an embedded-metadata package for a selected eligible file.

## Operating model

The analysis Mac never mutates the reviewed library. Copy the package to the media Mac, run `./apply.sh --dry-run "/path/to/library-root"`, inspect the output, then apply. Keep `.noside-mmm-backups/<job-id>` until Emby is verified.

## Deliberate limits

- TMDB matching is explicit. MMM will not auto-assign a bare filename to a search result because a wrong movie identity is worse than an unresolved one.
- Embedded tags are strongest for MP4/M4V/MOV. A tag-poor MKV is reported as needing TMDB review; it is never guessed.
- Current artwork is a poster JPG. Fanart/backdrops are not yet generated.
- Fingerprints use file size plus modification time, not a full media hash, to keep remote-library review fast and Monterey-friendly.
