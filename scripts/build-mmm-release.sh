#!/bin/sh
# One explicit release request. `both` creates one automatic MMM build
# identity, then reuses it in the macOS app and iPhone companion.
set -eu

if [ "$#" -ne 1 ] || { [ "$1" != "ios" ] && [ "$1" != "macos" ] && [ "$1" != "both" ]; }; then
  echo "Usage: $(basename "$0") ios|macos|both" >&2
  exit 64
fi

scope="$1"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
metadata=$(mktemp "${TMPDIR:-/tmp}/mmm-build-info.XXXXXX.plist")
trap 'rm -f "$metadata"' EXIT
"$root/scripts/generate-mmm-build-info.sh" "$metadata"
export MMM_BUILD_INFO_SOURCE="$metadata"

if [ "$scope" = "macos" ] || [ "$scope" = "both" ]; then
  "$root/scripts/package-micromm-macos.sh"
fi
if [ "$scope" = "ios" ] || [ "$scope" = "both" ]; then
  xcodebuild -project "$root/Companion iOS/NoSideMediaCompanion.xcodeproj" \
    -scheme NoSideMediaCompanion -configuration Release -sdk iphoneos \
    -destination 'generic/platform=iOS' build
fi
