#!/bin/sh
# Local and CI verification for the single unified MMM Xcode project.
# This does not sign, package, deploy, launch, or touch a media library.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
project="$root/NoSideMediaManager.xcodeproj"
macos_destination="platform=macOS,arch=$(uname -m)"

swift test --package-path "$root"
xcodebuild -quiet -project "$project" -scheme microMM -configuration Debug build \
  -destination "$macos_destination"
# Swift Package Manager executes the shared tests above.  Keep Xcode's check to
# compiling the same test bundle: `xcodebuild test` has stalled while launching
# the macOS test runner on hosted CI runners.
xcodebuild -quiet -project "$project" -scheme NoSideMediaManagerTests -configuration Debug build-for-testing \
  -destination "$macos_destination"
xcodebuild -quiet -project "$project" -scheme noside-media -configuration Debug build \
  -destination "$macos_destination"
xcodebuild -quiet -project "$project" -scheme microMMCompanion -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
