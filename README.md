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

Alternatively, store a credential in the current Mac user's Keychain (outside
the repository and job bundles). This avoids placing it in shell history:

```sh
read -s 'TVDB API key: ' key; echo
security add-generic-password -U -a "$USER" -s 'NoSideMediaManager.TVDB_API_KEY' -w "$key"
unset key
```

Use the same command with `TVDB_PIN` only when your API key requires a PIN.
Environment variables take precedence over Keychain values.

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
