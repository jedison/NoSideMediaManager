# Implementation phases

## Phase 1 — NFO foundation (current)

- [x] Provider abstraction and TVDB v4 adapter.
- [x] Series search and official English episode retrieval.
- [x] Basic `tvshow.nfo` and episode NFO rendering.
- [x] macOS SwiftUI shell and command-line entry point.
- [x] Tests for XML escaping and no-partial-write conflicts.

## Phase 2 — Media matching

- [ ] Inspect an existing series folder and match NFO names to video files.
- [x] Scan common video extensions and propose number-for-number TVDB matches.
- [ ] Present and require approval of local ↔ canonical ↔ Emby season/episode
  mappings before writing beside an existing video.
- [x] Provide reusable per-file canonical-episode selection for ambiguous runs.
- [x] Generate a quoted Bash rename script or execute a reviewed local rename
  plan with conflict preflight and a reverse plan.
- [ ] Review unmatched / ambiguous episodes before writing.
- [ ] Add a per-series overwrite confirmation in the UI.

## Phase 3 — richer metadata

- [x] Download approved episode artwork without overwriting an existing file.
- [ ] Artwork and cast/crew policy.
- [ ] Translation and episode-order selection.
- [ ] Add a second source through `TVMetadataSource`.
