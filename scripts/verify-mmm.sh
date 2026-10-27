#!/bin/sh
# Local and CI verification for the single unified MMM Xcode project.
# This does not sign, package, deploy, launch, or touch a media library.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
project="$root/NoSideMediaManager.xcodeproj"

swift test --package-path "$root"
xcodebuild -quiet -project "$project" -scheme microMM -configuration Debug build \
  -destination 'platform=macOS'
xcodebuild -quiet -project "$project" -scheme NoSideMediaManagerTests -configuration Debug test \
  -destination 'platform=macOS'
xcodebuild -quiet -project "$project" -scheme noside-media -configuration Debug build \
  -destination 'platform=macOS'
xcodebuild -quiet -project "$project" -scheme microMMCompanion -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
