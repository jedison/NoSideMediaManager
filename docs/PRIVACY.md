# Privacy

NoSide Media Manager is local-first. It reads only the files and folders you
select and writes media-library changes only through an explicitly reviewed,
portable job package.

- TVDB and TMDB requests are made only when you invoke a lookup or create a
  package that needs provider data.
- API keys and Companion pairing tokens stay on the local Mac, in the current
  shell environment or Keychain as configured. They are never committed to the
  repository.
- The project has no analytics, telemetry, or hosted NoSide service.
- A generated job can contain local file names, paths, metadata, and artwork.
  Treat it as private when moving, sharing, or archiving it.
- The optional Companion server is authenticated with its locally configured
  pairing token. Do not expose it to the public internet.

Third-party services have their own terms and privacy policies. See
[third-party notices](THIRD_PARTY_NOTICES.md).
