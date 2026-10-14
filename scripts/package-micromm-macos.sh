#!/bin/sh
# Build an Intel-compatible microMM app. Provide MMM_SIGNING_IDENTITY when a
# distributable signing identity is available; otherwise the app is ad-hoc signed.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
output="${1:-$root/build/release/microMM.app}"
scratch="${MMM_SWIFT_SCRATCH:-/tmp/noside-mmm-release-build}"
identity="${MMM_SIGNING_IDENTITY:--}"

swift build -c release --arch x86_64 --product noside-media --scratch-path "$scratch"
swift build -c release --arch x86_64 --product NoSideMediaManagerApp --scratch-path "$scratch"

rm -rf "$output"
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
cp "$root/distribution/microMM/Info.plist" "$output/Contents/Info.plist"
cp "$scratch/out/Products/Release/NoSideMediaManagerApp" "$output/Contents/MacOS/NoSideMediaManagerApp"
cp "$scratch/out/Products/Release/noside-media" "$output/Contents/MacOS/noside-media"
cp "$root/Resources/AppIcon.icns" "$output/Contents/Resources/AppIcon.icns"
"$root/scripts/generate-mmm-build-info.sh" "$output/Contents/Resources/MMMBuildInfo.plist"
codesign --force --deep --sign "$identity" "$output"
codesign --verify --deep --strict --verbose=2 "$output"
printf '%s\n' "$output"
