#!/bin/zsh
# Reserve one globally unique MMM build number for a distributable iOS or
# macOS build, then synchronise derived packaging metadata.
set -euo pipefail

if [[ $# -ne 1 || ( "$1" != "ios" && "$1" != "macos" ) ]]; then
  print -u2 "Usage: $(basename "$0") ios|macos"
  exit 64
fi

component="$1"
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
  print "Would reserve NoSide Media Manager $version (build $next_build) for $component."
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

print "Reserved NoSide Media Manager $version (build $next_build) for $component."
print "Build that component now. A later build of either platform must reserve another number."
