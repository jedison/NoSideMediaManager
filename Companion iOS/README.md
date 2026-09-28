# MMM Companion for iPhone

Native iOS companion for the MMM Companion tab in the original macOS MMM app.
It pairs using the old MBA's local address, port, and one pairing token. The
phone can list frozen jobs, run a dry-run, request an explicit confirmed apply,
or request rollback. It never mounts or receives unrestricted access to the
movie volume.

The iPhone companion shares microMM's release identity. This source currently
builds as version **0.4.9**, build **10**, matching the macOS microMM app and
its bundled CLI.

Open `NoSideMediaCompanion.xcodeproj` in Xcode, select your development team,
then install it to an iPhone. The app targets iOS 16+.
