# MMM Companion for iPhone

Native iOS companion for the MMM Companion tab in the original macOS MMM app.
It pairs using the media server's local address, port, and one pairing token. The
phone can list frozen jobs, run a dry-run, request an explicit confirmed apply,
or request rollback. It never mounts or receives unrestricted access to the
movie volume.

The iPhone companion follows the Upgrade/Walletize automatic build-info
pattern. Each build embeds a local sequence and UTC timestamp in
`MMMBuildInfo.plist`. A coordinated `build-mmm-release.sh both` release gives
the iPhone and macOS app the same generated identity.

Open `NoSideMediaCompanion.xcodeproj` in Xcode, select your development team,
then install it to an iPhone. The app targets iOS 16+.
