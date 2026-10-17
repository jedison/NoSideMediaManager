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
common_git_dir=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
release_lock="${common_git_dir:-$root/.git}/mmm-release.lock"
if ! mkdir "$release_lock" 2>/dev/null; then
  echo "Another MMM release is already being packaged; wait for it to finish before retrying." >&2
  exit 75
fi
metadata_base=$(mktemp "${TMPDIR:-/tmp}/mmm-build-info.XXXXXX")
rm -f "$metadata_base"
metadata="${metadata_base}.plist"
cleanup() {
  rm -f "$metadata"
  rmdir "$release_lock" 2>/dev/null || true
}
trap cleanup EXIT
if [ -n "${MMM_BUILD_INFO_SOURCE:-}" ]; then
  test -f "$MMM_BUILD_INFO_SOURCE"
  cp "$MMM_BUILD_INFO_SOURCE" "$metadata"
else
  "$root/scripts/generate-mmm-build-info.sh" "$metadata"
fi
export MMM_BUILD_INFO_SOURCE="$metadata"

if [ "$scope" = "macos" ] || [ "$scope" = "both" ]; then
  "$root/scripts/package-micromm-macos.sh"
fi
if [ "$scope" = "ios" ] || [ "$scope" = "both" ]; then
  # Keep the installable iOS bundle's version fields—not merely its embedded
  # About resource—on the exact same generated identity as microMM macOS.
  sequence=$(/usr/libexec/PlistBuddy -c 'Print :sequence' "$metadata")
  version=$(/usr/libexec/PlistBuddy -c 'Print :version' "$metadata")
  xcodebuild -project "$root/NoSideMediaManager.xcodeproj" \
    -scheme microMMCompanion -configuration Release -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    CURRENT_PROJECT_VERSION="$sequence" MARKETING_VERSION="$version" build
fi
