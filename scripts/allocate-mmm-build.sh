#!/bin/zsh
# Reserve one globally unique MMM build number for a requested distributable
# release, then synchronise derived packaging metadata.
set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "ios" && "$1" != "macos" && "$1" != "both" ) ]]; then
  print -u2 "Usage: $(basename "$0") ios|macos|both"
  exit 64
fi

release_scope="$1"
root="$(cd "$(dirname "$0")/.." && pwd)"
registry="$root/release/NoSideMediaManagerRelease.xcconfig"
lock="$root/release/.build-allocation.lock"

if ! mkdir "$lock" 2>/dev/null; then
  print -u2 "Another MMM build-number allocation is in progress. Try again shortly."
  exit 75
fi
trap 'rmdir "$lock"' EXIT

version="$(awk -F ' = ' '/^MMM_RELEASE_VERSION =/ { print $2; exit }' "$registry")"
build="$(awk -F ' = ' '/^MMM_RELEASE_BUILD =/ { print $2; exit }' "$registry")"
if [[ -z "$version" || ! "$build" =~ '^[0-9]+$' ]]; then
  print -u2 "Invalid release registry: $registry"
  exit 65
fi

next_build=$((build + 1))
if [[ "${MMM_RELEASE_DRY_RUN:-0}" == "1" ]]; then
  print "Would reserve NoSide Media Manager $version (build $next_build) for $release_scope."
  exit 0
fi
temporary="$(mktemp "$registry.XXXXXX")"
awk -v next_build="$next_build" '
  /^MMM_RELEASE_BUILD =/ { print "MMM_RELEASE_BUILD = " next_build; next }
  { print }
' "$registry" > "$temporary"
mv "$temporary" "$registry"

print -r -- "$version" > "$root/VERSION"
print -r -- "$version" > "$root/distribution/noside-media/VERSION"
for plist in "$root/distribution/microMM/Info.plist"; do
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next_build" "$plist"
done

print "Reserved NoSide Media Manager $version (build $next_build) for $release_scope."
if [[ "$release_scope" == "both" ]]; then
  print "Build and distribute both macOS and iOS artifacts with this same number."
else
  print "Build and distribute the $release_scope artifact now. A later release reserves another number."
fi
