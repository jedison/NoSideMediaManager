# microMM — Pre-test status

Updated: 2026-10-07

## Current delivery

- macOS microMM build 74 is deployed to the media server.
- Source commit: `d542c61` — `Strengthen TV mapping review and companion freeze`.
- The macOS app, embedded CLI, and Companion service are aligned in that app bundle.
- The release did not change media-library content. Library mutations remain available only through a reviewed frozen package and its `apply.sh` script.
- Verification completed locally: 55 Swift tests, a macOS app build, and an iOS Release build. The iOS app is deliberately not deployed.

## Immediate acceptance test

Run a copied-one-season GBBO pilot:

1. Audit, search, and explicitly map the copied season.
2. Review duplicate, NFO, destination, and artwork decisions.
3. Freeze a portable package and inspect its preview.
4. Dry-run it on the media server.
5. Apply it, rescan/check in Emby, and verify episode ordering and sidecars.
6. Run rollback and verify that the original copied fixture is restored.

## Known work before or alongside broader testing

- Validate real iPhone pairing and a frozen job’s dry-run, apply, rollback, and operation-log display once deployment reopens.
- Add field-by-field TV NFO merge/acceptance. The current review displays fields that differ, but an applied package writes the complete reviewed TVDB NFO.
- Add saved TV-review sort preferences and richer canonical-episode search facets.
- Add named, source-relative reusable TV mapping preset collections. Current editable JSON plans work and record explicit exclusions.
- Add stronger ZIP integrity/checksum verification.
- Record TVDB API fixtures for episode orders, artwork, pagination, and error cases to make provider testing repeatable/offline.

## Deferred product scope

- iOS pairing token in Keychain, QR pairing, Bonjour discovery, and supported multiple media/job-root mappings.
- Movie sidecar keep/move/replace controls beyond poster choice; richer embedded metadata extraction.
- Season-level TVDB metadata/artwork, optional movie fanart/backdrops, edition/extras/trailer handling, orphan-sidecar review, subtitle language review, and opt-in Emby rescan guidance.

## Open decisions

1. Whether NFOs should always live beside media or in a metadata staging location.
2. Which episode order should be the default when TVDB offers alternatives.
3. Whether later providers should enrich TVDB records or remain separate, competing reference sources.
