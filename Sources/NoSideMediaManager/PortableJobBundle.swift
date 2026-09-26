import Foundation

/// A frozen, transferable change set. It contains no absolute media-library
/// paths: `apply.sh` and `rollback.sh` receive the show root at execution time.
public struct PortableJobManifest: Codable, Sendable, Equatable {
    public struct Move: Codable, Sendable, Equatable {
        public let source: String
        public let destination: String
    }

    public let formatVersion: Int
    public let jobID: String
    public let seriesTVDBID: Int
    public let seriesTitle: String
    public let moves: [Move]
    public let generatedFiles: [String]
    public let unavailableArtwork: [String]

    public init(jobID: String, series: TVSeries, moves: [Move], generatedFiles: [String], unavailableArtwork: [String] = []) {
        self.formatVersion = 1
        self.jobID = jobID
        self.seriesTVDBID = series.tvdbID
        self.seriesTitle = series.title
        self.moves = moves
        self.generatedFiles = generatedFiles
        self.unavailableArtwork = unavailableArtwork
    }
}

public enum PortableJobBundleError: LocalizedError, Equatable {
    case unresolvedMapping
    case outputAlreadyExists(URL)
    case pathOutsideShowRoot(URL)

    public var errorDescription: String? {
        switch self {
        case .unresolvedMapping: "Every selected video needs a canonical TVDB episode before a job can be frozen."
        case .outputAlreadyExists(let url): "The job bundle output already exists: \(url.path)"
        case .pathOutsideShowRoot(let url): "A planned path is outside the selected show root: \(url.path)"
        }
    }
}

/// Builds a directory which can be copied or zipped without bringing along the
/// media files. The builder only writes inside `bundle`; it never changes
/// `showRoot`.
public enum PortableJobBundle {
    @discardableResult
    public static func create(
        at bundle: URL,
        showRoot: URL,
        series: TVSeries,
        mappings: [ApprovedEpisodeMapping],
        destinations: [URL: URL] = [:],
        downloadArtwork: Bool = true,
        fileManager: FileManager = .default
    ) async throws -> PortableJobManifest {
        guard !fileManager.fileExists(atPath: bundle.path) else { throw PortableJobBundleError.outputAlreadyExists(bundle) }
        let root = showRoot.standardizedFileURL
        let jobID = "mmm-\(UUID().uuidString.lowercased())"
        let moves = try mappings.compactMap { mapping -> PortableJobManifest.Move? in
            let source = try relative(mapping.local.url, to: root)
            let destinationURL = destinations[mapping.local.url] ?? mapping.local.url
            let destination = try relative(destinationURL, to: root)
            return source == destination ? nil : .init(source: source, destination: destination)
        }

        try fileManager.createDirectory(at: bundle.appendingPathComponent("generated"), withIntermediateDirectories: true)
        var generated = ["tvshow.nfo"]
        var unavailableArtwork = [String]()
        var artworkJobs = [ArtworkJob]()
        try write(NFOWriter.seriesData(series), relativePath: "tvshow.nfo", in: bundle)

        let outputLocations = try mappings.map { mapping -> (ApprovedEpisodeMapping, String) in
            let destination = destinations[mapping.local.url] ?? mapping.local.url
            return (mapping, try relative(destination, to: root))
        }
        for (mapping, videoPath) in outputLocations {
            let nfoPath = replacingExtension(videoPath, with: "nfo")
            if !generated.contains(nfoPath) {
                try write(NFOWriter.episodeData(mapping.canonical), relativePath: nfoPath, in: bundle)
                generated.append(nfoPath)
            }
            if downloadArtwork, mapping.downloadArtwork, let artwork = mapping.canonical.artworkURL {
                let jpgPath = replacingExtension(videoPath, with: "jpg")
                let target = generatedURL(for: jpgPath, in: bundle)
                if !generated.contains(jpgPath) && !artworkJobs.contains(where: { $0.path == jpgPath }) {
                    try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                    artworkJobs.append(ArtworkJob(path: jpgPath, url: artwork, target: target))
                }
            }
        }
        await withTaskGroup(of: ArtworkResult.self) { group in
            for job in artworkJobs {
                group.addTask {
                    do {
                        _ = try await ArtworkDownloader.download(job.url, to: job.target)
                        return ArtworkResult(path: job.path)
                    } catch {
                        return ArtworkResult(path: job.path, failure: error.localizedDescription)
                    }
                }
            }
            for await result in group {
                if let failure = result.failure {
                    // An absent/expired image must not prevent the reviewed,
                    // otherwise complete NFO/rename transaction from being portable.
                    unavailableArtwork.append("\(result.path): \(failure)")
                } else {
                    generated.append(result.path)
                }
            }
        }
        let byFolder = Dictionary(grouping: outputLocations, by: { ($0.1 as NSString).deletingLastPathComponent })
        for (folder, items) in byFolder {
            // A regular season folder can include an aired special (season 0).
            // Its season.nfo should still describe the dominant regular season.
            let counts = Dictionary(grouping: items, by: { $0.0.canonical.season }).mapValues(\.count)
            guard let season = counts.filter({ $0.key > 0 }).max(by: { lhs, rhs in lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value })?.key else { continue }
            let path = folder.isEmpty || folder == "." ? "season.nfo" : folder + "/season.nfo"
            try write(NFOWriter.seasonData(number: season), relativePath: path, in: bundle)
            generated.append(path)
        }

        generated.sort()
        let manifest = PortableJobManifest(jobID: jobID, series: series, moves: moves, generatedFiles: generated, unavailableArtwork: unavailableArtwork.sorted())
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: bundle.appendingPathComponent("manifest.json"), options: .atomic)
        try script(applyScript(manifest), named: "apply.sh", in: bundle)
        try script(rollbackScript(manifest), named: "rollback.sh", in: bundle)
        try readme(manifest).data(using: .utf8)!.write(to: bundle.appendingPathComponent("README.txt"), options: .atomic)
        return manifest
    }

    private static func relative(_ url: URL, to root: URL) throws -> String {
        let path = url.standardizedFileURL.path
        let rootPath = root.path
        guard path.hasPrefix(rootPath + "/") else { throw PortableJobBundleError.pathOutsideShowRoot(url) }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func replacingExtension(_ path: String, with extensionName: String) -> String {
        ((path as NSString).deletingPathExtension as NSString).appendingPathExtension(extensionName) ?? path
    }

    private static func generatedURL(for path: String, in bundle: URL) -> URL {
        bundle.appendingPathComponent("generated").appendingPathComponent(path)
    }

    private static func write(_ data: Data, relativePath: String, in bundle: URL) throws {
        let output = generatedURL(for: relativePath, in: bundle)
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: output, options: .atomic)
    }

    private static func script(_ text: String, named name: String, in bundle: URL) throws {
        let url = bundle.appendingPathComponent(name)
        try text.data(using: .utf8)!.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func applyScript(_ manifest: PortableJobManifest) -> String {
        let preflights = manifest.moves.map { "preflight_video \(quote($0.source)) \(quote($0.destination))" }.joined(separator: "\n")
        let moves = manifest.moves.map { "move_video \(quote($0.source)) \(quote($0.destination))" }.joined(separator: "\n")
        let generatedPreflights = manifest.generatedFiles.map { "preflight_generated \(quote($0))" }.joined(separator: "\n")
        let installs = manifest.generatedFiles.map { "install_generated \(quote($0))" }.joined(separator: "\n")
        return """
        #!/usr/bin/env bash
        # Frozen NoSide Media Manager job \(manifest.jobID). Generated; do not edit paths.
        set -euo pipefail
        shopt -s nullglob
        usage() { echo "Usage: $0 [--dry-run] /path/to/show-root" >&2; exit 64; }
        DRY_RUN=false; ROOT=""
        for arg in "$@"; do
          if [[ "$arg" == "--dry-run" ]]; then DRY_RUN=true
          elif [[ -z "$ROOT" ]]; then ROOT="$arg"
          else usage; fi
        done
        [[ -n "$ROOT" && -d "$ROOT" ]] || usage
        ROOT="$(cd "$ROOT" && pwd)"
        BUNDLE_DIR="$(cd "$(dirname "$0")" && pwd)"
        BACKUP_ROOT="$ROOT/.noside-mmm-backups/\(manifest.jobID)"
        CREATED="$BACKUP_ROOT/created-files.txt"
        run() { if $DRY_RUN; then printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\\n'; else "$@"; fi; }
        backup() { local rel target saved; rel="$1"; target="$ROOT/$rel"; saved="$BACKUP_ROOT/$rel"; [[ -e "$target" ]] || return 0; [[ -e "$saved" ]] && return 0; run mkdir -p "$(dirname "$saved")"; run cp -p "$target" "$saved"; }
        mark_created() { local rel="$1"; if [[ ! -e "$ROOT/$rel" ]]; then run mkdir -p "$BACKUP_ROOT"; if $DRY_RUN; then echo "DRY-RUN: record created $rel"; else printf '%s\\n' "$rel" >> "$CREATED"; fi; fi; }
        preflight_video() { [[ -f "$ROOT/$1" ]] || { echo "Missing video: $1" >&2; exit 1; }; [[ ! -e "$ROOT/$2" ]] || { echo "Destination video already exists: $2" >&2; exit 1; }; }
        preflight_generated() { [[ -f "$BUNDLE_DIR/generated/$1" ]] || { echo "Bundle is missing generated/$1" >&2; exit 1; }; }
        move_optional() { local src="$1" dst="$2"; [[ -e "$ROOT/$src" ]] || return 0; backup "$dst"; run mkdir -p "$(dirname "$ROOT/$dst")"; run mv "$ROOT/$src" "$ROOT/$dst"; }
        move_video() {
          local src="$1" dst="$2" srcbase="${1%.*}" dstbase="${2%.*}" suffix sidecar target
          [[ -f "$ROOT/$src" ]] || { echo "Missing video: $src" >&2; exit 1; }
          [[ ! -e "$ROOT/$dst" ]] || { echo "Destination video already exists: $dst" >&2; exit 1; }
          run mkdir -p "$(dirname "$ROOT/$dst")"; run mv "$ROOT/$src" "$ROOT/$dst"
          # NFO is regenerated. Preserve it for rollback instead of trusting it as metadata.
          if [[ -e "$ROOT/$srcbase.nfo" ]]; then backup "$srcbase.nfo"; run rm -f "$ROOT/$srcbase.nfo"; fi
          # Preserve old image sidecars when new TVDB artwork is bundled; otherwise move them.
          for sidecar in "$ROOT/$srcbase".{jpg,jpeg,png}; do
            [[ -e "$sidecar" ]] || continue; suffix="${sidecar#"$ROOT/$srcbase"}"; target="$dstbase$suffix"
            if [[ -f "$BUNDLE_DIR/generated/$dstbase.jpg" ]]; then backup "$srcbase$suffix"; run rm -f "$sidecar"; else move_optional "$srcbase$suffix" "$target"; fi
          done
          # Language-bearing subtitle suffixes are retained, e.g. .en.srt.
          for sidecar in "$ROOT/$srcbase"*.{srt,ass,ssa,sub,idx,vtt}; do
            [[ -e "$sidecar" ]] || continue; suffix="${sidecar#"$ROOT/$srcbase"}"; move_optional "$srcbase$suffix" "$dstbase$suffix"
          done
        }
        install_generated() { local rel="$1"; [[ -f "$BUNDLE_DIR/generated/$rel" ]] || { echo "Bundle is missing generated/$rel" >&2; exit 1; }; backup "$rel"; mark_created "$rel"; run mkdir -p "$(dirname "$ROOT/$rel")"; run cp -p "$BUNDLE_DIR/generated/$rel" "$ROOT/$rel"; }
        # Validate the complete frozen plan before altering a media file.
        \(preflights)
        \(generatedPreflights)
        \(moves)
        \(installs)
        if $DRY_RUN; then echo "Dry run complete: no media-library files changed."; else echo "Applied \(manifest.jobID). Backup: $BACKUP_ROOT"; fi
        """
    }

    private static func rollbackScript(_ manifest: PortableJobManifest) -> String {
        let reverseMoves = manifest.moves.reversed().map { "rollback_video \(quote($0.destination)) \(quote($0.source))" }.joined(separator: "\n")
        return """
        #!/usr/bin/env bash
        # Reverses NoSide Media Manager job \(manifest.jobID) where its backup remains available.
        set -euo pipefail
        shopt -s nullglob
        usage() { echo "Usage: $0 [--dry-run] /path/to/show-root" >&2; exit 64; }
        DRY_RUN=false; ROOT=""
        for arg in "$@"; do if [[ "$arg" == "--dry-run" ]]; then DRY_RUN=true; elif [[ -z "$ROOT" ]]; then ROOT="$arg"; else usage; fi; done
        [[ -n "$ROOT" && -d "$ROOT" ]] || usage
        ROOT="$(cd "$ROOT" && pwd)"; BACKUP_ROOT="$ROOT/.noside-mmm-backups/\(manifest.jobID)"; CREATED="$BACKUP_ROOT/created-files.txt"
        [[ -d "$BACKUP_ROOT" ]] || { echo "Backup not found: $BACKUP_ROOT" >&2; exit 1; }
        run() { if $DRY_RUN; then printf 'DRY-RUN:'; printf ' %q' "$@"; printf '\\n'; else "$@"; fi; }
        rollback_optional() { local src="$1" dst="$2"; [[ -e "$ROOT/$src" ]] || return 0; [[ ! -e "$ROOT/$dst" ]] || { echo "Rollback collision: $dst" >&2; exit 1; }; run mkdir -p "$(dirname "$ROOT/$dst")"; run mv "$ROOT/$src" "$ROOT/$dst"; }
        rollback_video() { local src="$1" dst="$2" srcbase="${1%.*}" dstbase="${2%.*}" suffix sidecar; [[ -f "$ROOT/$src" ]] || { echo "Missing moved video: $src" >&2; exit 1; }; rollback_optional "$src" "$dst"; for sidecar in "$ROOT/$srcbase"*.{srt,ass,ssa,sub,idx,vtt,jpg,jpeg,png}; do [[ -e "$sidecar" ]] || continue; suffix="${sidecar#"$ROOT/$srcbase"}"; rollback_optional "$srcbase$suffix" "$dstbase$suffix"; done; }
        # Remove generated files that did not replace an original; then reverse moves.
        if [[ -f "$CREATED" ]]; then while IFS= read -r rel; do [[ -n "$rel" ]] && run rm -f "$ROOT/$rel"; done < "$CREATED"; fi
        \(reverseMoves)
        # Restore every original sidecar or destination collision saved by apply.sh.
        if $DRY_RUN; then echo "DRY-RUN: restore $BACKUP_ROOT into $ROOT"; else (cd "$BACKUP_ROOT" && find . -type f ! -name created-files.txt -exec sh -c 'root="$1"; shift; for f do d="$root/${f#./}"; mkdir -p "$(dirname "$d")"; cp -p "$f" "$d"; done' sh "$ROOT" {} +); fi
        if $DRY_RUN; then echo "Dry-run rollback complete: no media-library files changed."; else echo "Rollback complete for \(manifest.jobID). Keep or archive $BACKUP_ROOT after verification."; fi
        """
    }

    private static func readme(_ manifest: PortableJobManifest) -> String {
        """
        NoSide Media Manager portable job
        =================================
        Series: \(manifest.seriesTitle) (TVDB \(manifest.seriesTVDBID))
        Job: \(manifest.jobID)

        This package is intentionally portable: it contains generated XML/NFO and
        artwork, not any media files. It never embeds a machine-specific media path.

        On the Mac with the real library:
          ./apply.sh --dry-run "/path/to/\(manifest.seriesTitle)"
          ./apply.sh "/path/to/\(manifest.seriesTitle)"

        To undo after a successful apply:
          ./rollback.sh --dry-run "/path/to/\(manifest.seriesTitle)"
          ./rollback.sh "/path/to/\(manifest.seriesTitle)"

        Apply creates a local backup under `.noside-mmm-backups/\(manifest.jobID)`.
        Keep it until Emby and the files have been verified. `manifest.json` is the
        frozen review record; `generated/` holds the exact sidecars to be installed.
        \(manifest.unavailableArtwork.isEmpty ? "All requested TVDB episode artwork was bundled." : "TVDB artwork unavailable for \(manifest.unavailableArtwork.count) item(s); see manifest.json. NFOs and all available artwork are included.")
        """
    }

    private static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\"'\"'"))'"
    }
}

private struct ArtworkJob: Sendable {
    let path: String
    let url: URL
    let target: URL
}

private struct ArtworkResult: Sendable {
    let path: String
    let failure: String?
    init(path: String, failure: String? = nil) { self.path = path; self.failure = failure }
}
