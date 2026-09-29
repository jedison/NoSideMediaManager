# NoSide Media Manager

A deliberately small, local-first media metadata tool. Its first job is to
look up television series and episodes in TVDB, and movies in TMDB, then write
Kodi-compatible XML/NFO sidecar files beside the media.

Every NFO created by MMM includes Emby's `<lockdata>true</lockdata>` setting,
so Emby preserves MMM's reviewed metadata during later library scans. Existing
NFOs carried by a move-only preservation package are never rewritten.

Requires macOS Monterey 12 or later. It uses only Apple frameworks and has no
package dependencies.

## What is here

- `NoSideMediaManager`: provider-neutral TV metadata models, XML/NFO writer,
  TVDB v4 client, and an import service.
- `noside-media`: a small CLI for looking up a series, reviewing mappings, and
  freezing a portable filesystem-change job.

## One app, including the CLI

The deployed `microMM.app` contains the macOS interface, Companion server, and
the matching command-line executable. They are built from the same MMM core and
always share one release number. Run the bundled CLI directly when needed:

```sh
"~/NoSideMediaManagerJobs/microMM.app/Contents/MacOS/noside-media" --help
```

The older standalone `noside-media` deployment is retired rather than used.
Frozen jobs remain portable and do not need microMM installed to run their
`apply.sh` or `rollback.sh` scripts.

## Automatic build identity

MMM follows the Upgrade and Walletize pattern. Every ordinary app build writes
an automatic local sequence and UTC timestamp into `MMMBuildInfo.plist`; the
app and bundled CLI display it beside the normal Apple version/build fields.
The local counter is intentionally not committed.

For an explicit coordinated release, build both apps through one command:

```sh
./scripts/build-mmm-release.sh both
```

It creates one build identity once, then embeds that exact identity in both the
macOS app and iPhone companion. `ios` and `macos` are available when only one
artifact is being released.

Movie support uses TMDB and starts as a reviewed, one-movie-at-a-time workflow.

The network boundary is isolated in `TVDBClient`; NFO rendering needs no TVDB
credentials and is covered by fixture-based tests.

## TVDB credentials

Create a TVDB API key and optionally a subscriber PIN, then export them only
for the command you run:

```sh
export TVDB_API_KEY='…'
export TVDB_PIN='…' # omit when your key does not require it
```

MMM uses the current shell's environment by default and does not access
Keychain. That avoids repeated macOS consent prompts when the CLI is rebuilt
or run from Xcode. Keep the export in the Terminal session that runs MMM, or
place it in a private shell-startup file if that is appropriate for your Mac.

Keychain lookup remains a deliberate opt-in for advanced users only: set
`TVDB_USE_KEYCHAIN=1` in addition to creating the Keychain entry. Environment
variables always take precedence. Use `TVDB_PIN` only when your API key
requires a PIN.

For movie lookup, create a TMDB v3 API key and export it in the same private
Terminal session:

```sh
export TMDB_API_KEY='…'
```

## Usage

```sh
swift run noside-media search "The Bear"
swift run noside-media inspect "/Volumes/Movies/TV/Example/Example S01E01.m4v"
swift run noside-media inspect "/Volumes/Movies/TV/Example/Season 01"
swift run noside-media review 184871 "/Volumes/Media/TV/The Great British Bake Off"
```

`review` is read-only: it scans local video names and prints the proposed
TVDB official-order match for each file. Use it first on another Mac or an
external drive before writing any sidecars.

`inspect` is also read-only and needs no TVDB key. It prints embedded M4V/MP4
container facts—title, date, duration, dimensions, audio/subtitle languages,
and whether artwork is embedded—as JSON. These are review evidence, not an
automatic episode mapping.

For reviewed mappings and renames, use a transparent plan file:

```sh
./noside-media plan 184871 "/Volumes/Media/TV/GBBO" ~/Desktop/gbbo-plan.json
# Review/edit canonicalEpisodeID and optional destinationPath values, then:
./noside-media bundle ~/Desktop/gbbo-plan.json ~/Desktop/GBBO-mmm-job
```

For a show reviewed one season at a time, merge the approved plans and make a
separate, reviewable canonical-name plan before freezing the job. This retains
each existing season folder. Files for the same episode with different video
extensions retain the same basename; only an exact filename collision receives
an `Edition` suffix.

```sh
./noside-media merge-plans "/Volumes/Media/TV/GBBO" ~/Desktop/gbbo-combined.json ~/Desktop/Season-*.json
./noside-media normalize-plan ~/Desktop/gbbo-combined.json ~/Desktop/gbbo-normalized.json
./noside-media bundle ~/Desktop/gbbo-normalized.json ~/Desktop/GBBO-mmm-job
```

If TVDB is temporarily unavailable after a normalized plan has already been
reviewed, use `bundle --offline`. It reconstructs the essential NFO fields
(title, season, episode, and TVDB IDs) from canonical filenames and creates
the same portable rename/NFO package without contacting TVDB. It deliberately
does not add fresh TVDB artwork, descriptions, air dates, or ratings; existing
image sidecars still follow their video files during the rename.

```sh
./noside-media bundle ~/Desktop/gbbo-normalized.json ~/Desktop/GBBO-mmm-job --offline
```

`bundle` only writes the new job folder on the analysis Mac. It never writes to
the reviewed library. Copy or ZIP that folder to the Mac connected to the
media, then run:

```sh
cd GBBO-mmm-job
./apply.sh --dry-run "/path/to/The Great British Bake Off"
./apply.sh "/path/to/The Great British Bake Off"
```

Each frozen job contains `apply.sh`, `rollback.sh`, `manifest.json`, a
`generated/` tree of exact NFO/artwork sidecars, and a short `README.txt`.
The scripts create a local, job-specific backup before replacing NFO/JPG
sidecars, moving videos, or moving subtitle companions. Review the dry-run and
keep that backup until the media-server scan is verified.

## Movies (TMDB)

Movie work is package-only: the analysis Mac does not write the movie library.
Search TMDB, create an editable plan with the selected TMDB ID, normalize it,
then freeze a portable job. The canonical default filename is `Title (Year)`.

```sh
swift run noside-media movie-search "The Matrix"
swift run noside-media movie-tvdb-search "The Matrix" # optional comparison
swift run noside-media movie-plan 603 "/Volumes/Movies/Movies" \
  "/Volumes/Movies/Movies/Incoming/Matrix.mkv" ~/Desktop/matrix-plan.json
# Review the tmdbID in the JSON, then:
swift run noside-media movie-normalize-plan ~/Desktop/matrix-plan.json ~/Desktop/matrix-normalized.json
swift run noside-media movie-bundle ~/Desktop/matrix-normalized.json ~/Desktop/Matrix-mmm-job
```

To opt into a one-folder-per-movie layout, add `--movie-folders` while
normalizing. The generated job moves the video and all supported companion
sidecars below `Title (Year)/`; it remains reviewable and reversible.

```sh
swift run noside-media movie-normalize-plan ~/Desktop/matrix-plan.json \
  ~/Desktop/matrix-folders.json --movie-folders
```

The job contains a `<movie>` NFO with TMDB identity and requested poster JPG,
plus the same `apply.sh --dry-run`, apply, and rollback process as TV jobs.
Use `--no-artwork` when a job should retain an existing poster sidecar.
`movie-bundle` also accepts a normalized plan with several explicitly reviewed
entries and freezes them as one target-Mac transaction.

Start by auditing a movie tree. The JSON report identifies videos that are
already complete, those whose own container tags/artwork can be preserved, and
bare videos that need a reviewed TMDB match:

```sh
swift run noside-media movie-audit "/Volumes/Movies/Movies" > ~/Desktop/movie-audit.json
```

For duplicate TMDB IDs, invalid movie NFO XML, missing sidecars, and likely
editions/extras, generate the related health report:

```sh
swift run noside-media movie-health "/Volumes/Movies/Movies" > ~/Desktop/movie-health.json
```

For an `embeddedMetadataNeedsSidecars` item, freeze sidecars from its existing
container title/date/cover art—without TMDB or a rename:

```sh
swift run noside-media movie-embedded-bundle "/Volumes/Movies/Movies" \
  "/Volumes/Movies/Movies/Example.mp4" ~/Desktop/Example-embedded-job
```

Items marked `bareNeedsTMDB` intentionally remain unmodified until you choose
a TMDB result with `movie-search`, then use the reviewed plan workflow above.
`movie-tvdb-search` is available alongside it as a TVDB comparison source. It
does not auto-merge provider identities or change the selected TMDB NFO ID.

### Preserve and normalise existing complete movies

For films already carrying a valid TMDB movie NFO and primary poster, use the
preservation route. It needs no API key and never regenerates XML or artwork.
It proposes a `Title (Year)/Title (Year).ext` layout, then freezes a move-only
job that carries the existing NFO, `-poster`, `-fanart`, `-clearlogo`, and
subtitle sidecars along unchanged.

```sh
swift run noside-media movie-preservation-plan "/Volumes/Movies/My/Movies" \
  ~/Desktop/movie-preservation-plan.json
# Review/edit destinationPath values in this JSON before freezing it.
swift run noside-media movie-preservation-bundle \
  ~/Desktop/movie-preservation-plan.json ~/Desktop/movie-preservation-job
cd ~/Desktop/movie-preservation-job
./apply.sh --dry-run "/Volumes/Movies/My/Movies"
./apply.sh "/Volumes/Movies/My/Movies"
```

The Movies screen provides the same two steps as **Export preservation plan**
and **Freeze preservation package**. The package refuses source changes or any
destination collision before moving its first file, and `rollback.sh` reverses
the folder/file moves.

When the analysis Mac can read a source video, MMM records its size and
modification time in `manifest.json`. `apply.sh` rechecks it and refuses a
changed file. Remote-path-only plans remain supported but cannot include that
optional fingerprint.

Add `--sha256` to TV or movie `bundle` commands when the analysis Mac can read
the files and you want a stronger, slower content hash in the frozen job.

Run the native macOS interface from Xcode by opening `Package.swift`, or from a
terminal with:

```sh
swift run NoSideMediaManagerApp
```

## Development

```sh
swift test
```

No credentials, media files, or artwork are stored in this repository.
