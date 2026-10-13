#!/bin/sh
# Build a universal, signed microMM app: Intel keeps Catalina-era Macs
# supported while Apple Silicon avoids requiring Rosetta on a Media Mac mini.
# The generated MMMBuildInfo resource is created here, or copied from a
# coordinated release identity.
set -eu

root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
output="${1:-$root/build/release/microMM.app}"
scratch="${MMM_SWIFT_SCRATCH:-/tmp/noside-mmm-release-build}"
arm_scratch="${MMM_SWIFT_ARM_SCRATCH:-/tmp/noside-mmm-release-build-arm64}"
identity="${MMM_SIGNING_IDENTITY:-Apple Development: your-apple-developer-account@example.com (YOURTEAMID)}"

swift build -c release --arch x86_64 --product noside-media --scratch-path "$scratch"
swift build -c release --arch x86_64 --product NoSideMediaManagerApp --scratch-path "$scratch"
swift build -c release --arch arm64 --product noside-media --scratch-path "$arm_scratch"
swift build -c release --arch arm64 --product NoSideMediaManagerApp --scratch-path "$arm_scratch"

rm -rf "$output"
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
cp "$root/distribution/microMM/Info.plist" "$output/Contents/Info.plist"
lipo -create \
  "$scratch/out/Products/Release/NoSideMediaManagerApp" \
  "$arm_scratch/out/Products/Release/NoSideMediaManagerApp" \
  -output "$output/Contents/MacOS/NoSideMediaManagerApp"
lipo -create \
  "$scratch/out/Products/Release/noside-media" \
  "$arm_scratch/out/Products/Release/noside-media" \
  -output "$output/Contents/MacOS/noside-media"
cp "$root/Resources/AppIcon.icns" "$output/Contents/Resources/AppIcon.icns"
"$root/scripts/generate-mmm-build-info.sh" "$output/Contents/Resources/MMMBuildInfo.plist"
sequence=$(/usr/libexec/PlistBuddy -c 'Print :sequence' "$output/Contents/Resources/MMMBuildInfo.plist")
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $sequence" "$output/Contents/Info.plist"
codesign --force --deep --sign "$identity" "$output"
codesign --verify --deep --strict --verbose=2 "$output"
printf '%s\n' "$output"
