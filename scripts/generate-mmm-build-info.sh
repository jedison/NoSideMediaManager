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

# Store the automatic sequence in Git's shared metadata directory.  Unlike a
# source-root counter this is shared by the main checkout and every worktree,
# so a coordinated iOS/macOS release cannot accidentally reuse an older number.
if [ -n "${MMM_BUILD_COUNTER_FILE:-}" ]; then
  counter_file="$MMM_BUILD_COUNTER_FILE"
else
  common_git_dir=$(git -C "$root" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  if [ -n "$common_git_dir" ]; then
    counter_file="$common_git_dir/mmm-build-counter"
  else
    counter_file="$root/.mmm-build-counter"
  fi
fi
lock="${counter_file}.lock"
if ! mkdir "$lock" 2>/dev/null; then
  echo "Another MMM build is already creating build metadata." >&2
  exit 75
fi
trap 'rmdir "$lock"' EXIT

version=$(tr -d '[:space:]' < "$root/VERSION")
initial_bundle_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$root/distribution/microMM/Info.plist")

# The first automatic sequence continues the shipped app's existing build
# number; subsequent values come solely from the local, ignored counter.
counter="$initial_bundle_build"
if [ -f "$counter_file" ]; then
  counter=$(tr -d '[:space:]' < "$counter_file")
else
  # One-time migration from original checkout-local counters.  A worktree can
  # have its own stale counter, so take the highest valid legacy sequence.
  for legacy_counter in "$root/.mmm-build-counter" "${common_git_dir:+$(dirname "$common_git_dir")/.mmm-build-counter}"; do
    if [ -f "$legacy_counter" ]; then
      legacy_value=$(tr -d '[:space:]' < "$legacy_counter")
      case "$legacy_value" in
        ''|*[!0-9]*) ;;
        *) if [ "$legacy_value" -gt "$counter" ]; then counter="$legacy_value"; fi ;;
      esac
    fi
  done
fi
case "$counter" in
  ''|*[!0-9]*) counter="$initial_bundle_build" ;;
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
/usr/libexec/PlistBuddy -c "Add :bundleBuild string $counter" "$output"
