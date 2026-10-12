#!/bin/bash
# Move MMM state from an existing media server to this new media server.
# Run this script *on the destination* (for example, MediaMacMini).
#
# It transfers only portable MMM state: frozen packages and non-Keychain
# preferences. It intentionally never copies a media library or Keychain data.
# Reconnect or physically move the external Movies volume separately.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  migrate-mmm-state-to-media-server.sh [--dry-run] \
    --source user@old-media-server \
    [--jobs-root ~/NoSideMediaManagerJobs] \
    [--movies-root /Volumes/Movies/My/Movies] \
    [--tv-root "/Volumes/Movies/My/TV Shows"]

Copies frozen MMM job folders and the MMM preference domain from the old server
to this Mac. It does NOT copy microMM.app, the media library, external disks,
or Keychain credentials (TVDB/TMDB keys must be entered in microMM Settings).

Run with --dry-run first. The destination jobs root must contain microMM.app.
EOF
  exit 64
}

dry_run=false
source_host=""
jobs_root="$HOME/NoSideMediaManagerJobs"
movies_root="/Volumes/Movies/My/Movies"
tv_root="/Volumes/Movies/My/TV Shows"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    --source) shift; [ "$#" -gt 0 ] || usage; source_host="$1" ;;
    --jobs-root) shift; [ "$#" -gt 0 ] || usage; jobs_root="$1" ;;
    --movies-root) shift; [ "$#" -gt 0 ] || usage; movies_root="$1" ;;
    --tv-root) shift; [ "$#" -gt 0 ] || usage; tv_root="$1" ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
  shift
done

[ -n "$source_host" ] || usage
[ -d "$jobs_root/microMM.app" ] || { echo "Destination microMM.app is missing: $jobs_root/microMM.app" >&2; exit 1; }

run() {
  if "$dry_run"; then
    printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

echo "Source: $source_host"
echo "Destination jobs: $jobs_root"
echo "Movie root to save: $movies_root"
echo "TV root to save: $tv_root"

ssh "$source_host" "test -d '$jobs_root'" || {
  echo "Cannot read the source jobs root at $jobs_root on $source_host." >&2
  exit 1
}

# Frozen jobs and their operation history are portable. Exclude app bundles and
# incoming/staging directories so the destination's known-good universal app is
# never replaced. Existing job folders remain; rsync's --ignore-existing makes
# this a non-destructive first pass.
run rsync -a --ignore-existing \
  --exclude 'microMM.app/' \
  --exclude 'microMM.app.previous-*/' \
  --exclude 'microMM.app.incoming-*/' \
  --exclude '.DS_Store' \
  "$source_host:$jobs_root/" "$jobs_root/"

# Preferences are copied through a temporary plist, not by copying the entire
# Preferences directory. This includes the pairing token and roots, but never
# Keychain entries. Save a local backup before importing.
preferences_tmp="$(mktemp "${TMPDIR:-/tmp}/noside-mmm-preferences.XXXXXX.plist")"
backup_tmp="$(mktemp "${TMPDIR:-/tmp}/noside-mmm-preferences-backup.XXXXXX.plist")"
trap 'rm -f "$preferences_tmp" "$backup_tmp"' EXIT

if "$dry_run"; then
  echo "DRY-RUN: ssh $source_host defaults export NoSideMediaManagerApp - > temporary preferences"
  echo "DRY-RUN: defaults export NoSideMediaManagerApp $backup_tmp"
  echo "DRY-RUN: defaults import NoSideMediaManagerApp temporary preferences"
else
  ssh "$source_host" 'defaults export NoSideMediaManagerApp -' > "$preferences_tmp" || true
  defaults export NoSideMediaManagerApp "$backup_tmp" 2>/dev/null || true
  if [ -s "$preferences_tmp" ]; then
    defaults import NoSideMediaManagerApp "$preferences_tmp"
  else
    echo "Source has no NoSideMediaManagerApp preference domain yet; continuing with requested roots."
  fi
  defaults write NoSideMediaManagerApp companion.jobsRoot -string "$jobs_root"
  defaults write NoSideMediaManagerApp companion.libraryRoot -string "$movies_root"
  defaults write NoSideMediaManagerApp companion.tvLibraryRoot -string "$tv_root"
fi

echo
echo "Migration state copied. Before using MMM:"
echo "  1. Attach/mount the external volume so the saved Movie and TV roots exist."
echo "  2. Open microMM and enter TVDB/TMDB keys in Settings (Keychain values are not migrated)."
echo "  3. Review Settings, then start Companion."
echo "  4. Verify imported frozen jobs with a dry-run before any apply."
