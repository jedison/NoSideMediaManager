# Architecture

```text
SwiftUI app / CLI
        │
        ▼
TVMetadataSource ◄── TVDBClient (v4 HTTP)
        │
        ▼
NFOWriter ───► PortableJobBundle ───► copied/ZIP package
                                      │
                                      ▼
                           target Mac: apply.sh / rollback.sh
```

`TVMetadataSource` defines the stable provider seam. `TVDBClient` owns the v4
login request and bearer-token use; the writer has no network dependency.

There is intentionally no persistence layer or database. The selected media
folder's NFO/XML files are the canonical, human-editable record.

Before an NFO is written beside an existing video, the future mapping layer
will show local filename identity, canonical provider identity, and the target
library identity separately. This is required because Emby derives TV episode
identity from filenames in cases where that conflicts with NFO season/episode
fields. GBBO is the reference case: UK aired order, Netflix/US collections, and
the local filenames can use different season schemes.

`PortableJobBundle` is the filesystem execution boundary. The analysis Mac can
scan, map, render NFO/XML, download selected artwork, and produce a frozen
bundle, but does not mutate the reviewed media library. Every bundle contains
relative paths only, `apply.sh`, `rollback.sh`, `manifest.json`, generated
sidecars, and a README. The target Mac supplies the show-root argument; an
`--dry-run` displays every mkdir, video move, NFO/JPG replacement, and subtitle
move before it is applied. A job-specific backup allows practical rollback.

The bundle generator fetches series and episode metadata concurrently,
calculates the complete output set, and writes only to its new package folder.
The initial NFO schema includes the series
or episode title, summary, dates, rating where available, genres, and TVDB IDs.

TVDB's v4 API requires an API key at `POST /login`, returns a bearer token, and
documents `GET /search`, `GET /series/{id}/extended`, and series episode-order
endpoints. See the [official TVDB v4 API documentation](https://thetvdb.github.io/v4-api/).

`MovieMetadataSource` is the equivalent small seam for TMDB. Movie NFOs use a
`<movie>` root and TMDB unique ID. Movie audit is read-only and reports sidecar
presence, existing movie-NFO validity/IDs, likely editions/extras, and
container-authored facts before a package is considered.

When a source is readable on the analysis Mac, a portable manifest records its
size and modification time. `apply.sh` rechecks that fingerprint before any
move. Remote-path-only plans retain normal existence/collision preflight but
cannot carry a source fingerprint.
