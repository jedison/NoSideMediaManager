#!/bin/sh
# Mirrors Upgrade/Walletize: create a build-local resource with an automatic
# sequence and UTC timestamp. A coordinated release can supply one prepared
# source plist through MMM_BUILD_INFO_SOURCE.
set -eu

if [ "$#" -ne 1 ]; then
  echo "Usage: $(basename "$0") OUTPUT_PLIST" >&2
  exit 64
fi

output="$1"
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)

if [ -n "${MMM_BUILD_INFO_SOURCE:-}" ]; then
  test -f "$MMM_BUILD_INFO_SOURCE"
  mkdir -p "$(dirname "$output")"
  cp "$MMM_BUILD_INFO_SOURCE" "$output"
  exit 0
fi

counter_file="${MMM_BUILD_COUNTER_FILE:-$root/.mmm-build-counter}"
lock="${counter_file}.lock"
if ! mkdir "$lock" 2>/dev/null; then
  echo "Another MMM build is already creating build metadata." >&2
  exit 75
fi
trap 'rmdir "$lock"' EXIT

version=$(tr -d '[:space:]' < "$root/VERSION")
bundle_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$root/distribution/microMM/Info.plist")

# The first automatic sequence continues the shipped app's existing build
# number; subsequent values come solely from the local, ignored counter.
counter="$bundle_build"
if [ -f "$counter_file" ]; then
  counter=$(tr -d '[:space:]' < "$counter_file")
fi
case "$counter" in
  ''|*[!0-9]*) counter="$bundle_build" ;;
esac
counter=$((counter + 1))
mkdir -p "$(dirname "$counter_file")"
printf '%s\n' "$counter" > "$counter_file"

timestamp=$(date -u '+%y%m%dZ%H%M%S')
mkdir -p "$(dirname "$output")"
/usr/bin/plutil -create xml1 "$output"
/usr/libexec/PlistBuddy -c "Add :sequence string $counter" "$output"
/usr/libexec/PlistBuddy -c "Add :timestamp string $timestamp" "$output"
/usr/libexec/PlistBuddy -c "Add :version string $version" "$output"
/usr/libexec/PlistBuddy -c "Add :bundleBuild string $bundle_build" "$output"
