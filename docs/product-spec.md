# Product specification

## Purpose

NoSide Media Manager gives a local media library a quick, reviewable path from
TVDB metadata to Kodi-compatible NFO sidecars.

The first release supports macOS Monterey 12 and later.

## 0.1 scope

1. Search TVDB for a television series.
2. Select a series and an existing destination folder.
3. Fetch its extended series record and official English episode order.
4. Write `tvshow.nfo` and `SxxExx.nfo` files.
5. Refuse to overwrite existing NFOs unless the user explicitly opts in.

After the mapping review, the app may either generate a Bash rename script or
execute the identical rename plan locally. Both paths show every proposed move
first, perform conflict preflight, and retain a reverse plan. Only then may the
app create sidecar NFOs and retrieve episode artwork.

A rename may also move an episode to another existing season folder. The plan
never creates destination folders implicitly; their paths are visible in the
review and must already exist.

When a video is renamed or moved, an existing same-basename `.nfo`, `.jpg`,
`.jpeg`, or `.png` companion is moved and renamed with it. NFO text and
attributes that reference the previous video filename are then updated.

TVDB's **official UK aired order** is the default series order. Therefore, *The
Great British Bake Off* is represented as one continuous show with seasons
1–17, rather than being split according to TMDB or Netflix/US collections.

## Episode identity and alternate orders

The app distinguishes three identities when they differ:

1. **Local identity** — the season/episode encoded in the existing filename.
2. **Canonical identity** — the source's original broadcast order, such as
   TVDB's UK aired order for *The Great British Bake Off*.
3. **Consumer identity** — the order a target library such as Emby will use.

They may be identical for ordinary series. They must be explicitly mapped and
reviewed when they are not—especially for UK versus Netflix/US releases. The
first importer does not yet perform that mapping, so it must not be used to
repair an existing GBBO library.

## Explicit non-goals

- Media-file discovery, rename/move, deletion, and library scanning.
- Artwork downloads, cast/crew enrichment, movies, and another metadata
  provider.
- Background scheduling and account persistence.
- Unreviewed filename renaming, moving, or changing an existing file's episode
  identity.

## Privacy and credentials

The API key and optional subscriber PIN are used only to authenticate directly
with TVDB. They are not written to the project directory. The selected folder
is the only local path modified.

## Metadata ownership

NFO/XML sidecars are the sole durable metadata store. The app keeps no database
or opaque metadata cache: each generated file remains readable and directly
editable in a text editor when a correction is needed. A later import must not
silently replace an existing NFO; replacement remains an explicit user choice.
