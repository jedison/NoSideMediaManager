# NoSide Media Manager

A deliberately small, local-first media metadata tool. Its first job is to
look up television series and episodes in TVDB and write Kodi-compatible NFO
sidecar files beside the media.

Requires macOS Monterey 12 or later. It uses only Apple frameworks and has no
package dependencies.

## What is here

- `NoSideMediaManager`: provider-neutral TV metadata models, XML/NFO writer,
  TVDB v4 client, and an import service.
- `noside-media`: a small CLI for looking up a series, reviewing mappings, and
  freezing a portable filesystem-change job.

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
