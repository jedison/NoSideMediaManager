import Foundation
@preconcurrency import AVFoundation

/// Non-authoritative facts embedded in a local video container. These are
/// useful evidence during review, particularly when filenames came from a
/// different regional release order, but never select a TVDB episode by
/// themselves.
public struct EmbeddedMediaInfo: Codable, Sendable, Equatable {
    public let fileName: String
    public let title: String?
    public let creationDate: String?
    public let durationSeconds: Double?
    public let width: Int?
    public let height: Int?
    public let audioLanguages: [String]
    public let subtitleLanguages: [String]
    public let hasEmbeddedArtwork: Bool
    /// Lightweight stable signature of embedded cover bytes.  MMM retains no
    /// image data in an audit; this lets the audit flag a real local mismatch.
    public let embeddedArtworkDigest: UInt64?
    public init(fileName: String, title: String?, creationDate: String?, durationSeconds: Double?, width: Int?, height: Int?, audioLanguages: [String], subtitleLanguages: [String], hasEmbeddedArtwork: Bool, embeddedArtworkDigest: UInt64? = nil) {
        self.fileName = fileName; self.title = title; self.creationDate = creationDate; self.durationSeconds = durationSeconds; self.width = width; self.height = height; self.audioLanguages = audioLanguages; self.subtitleLanguages = subtitleLanguages; self.hasEmbeddedArtwork = hasEmbeddedArtwork; self.embeddedArtworkDigest = embeddedArtworkDigest
    }
}

public enum MediaFileInspector {
    /// Common containers that MMM can audit and package without transcoding.
    /// A container that AVFoundation cannot inspect is still reported as a
    /// review item rather than omitted.
    private static let videoExtensions: Set<String> = ["m4v", "mkv", "mp4", "avi", "mov", "mpg", "mpeg", "wmv", "ts", "m2ts", "mts", "webm", "flv", "3gp"]

    /// Enumerates supported video containers without relying on their filename
    /// pattern, so older M4V libraries can be inspected before they are mapped.
    public static func videoFiles(in directory: URL, fileManager: FileManager = .default) -> [URL] {
        guard let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { videoExtensions.contains($0.pathExtension.lowercased()) }.sorted { $0.path < $1.path }
    }

    /// Reads QuickTime/M4V/MP4/MOV container metadata without modifying media.
    @MainActor
    public static func inspect(_ url: URL) async throws -> EmbeddedMediaInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        let tracks = try await asset.load(.tracks)
        let metadata = try await asset.load(.commonMetadata)
        let video = tracks.first { $0.mediaType == .video }
        let size = try await video?.load(.naturalSize)
        let artwork = metadata.first { $0.commonKey?.rawValue == "artwork" }?.dataValue
        return EmbeddedMediaInfo(
            fileName: url.lastPathComponent,
            title: stringValue(for: "title", in: metadata),
            creationDate: stringValue(for: "creationDate", in: metadata),
            durationSeconds: duration.isNumeric ? duration.seconds : nil,
            width: size.map { Int($0.width.rounded()) },
            height: size.map { Int($0.height.rounded()) },
            audioLanguages: try await languages(for: tracks, type: .audio),
            subtitleLanguages: try await languages(for: tracks, type: .subtitle),
            hasEmbeddedArtwork: artwork != nil,
            embeddedArtworkDigest: artwork.map(artworkDigest)
        )
    }

    /// Extracts only container-authored movie facts and cover bytes. No lookup
    /// or filename inference occurs here, so it is safe for preservation jobs.
    @MainActor
    public static func extractMovieMetadata(_ url: URL) async throws -> EmbeddedMovieMetadata {
        let asset = AVURLAsset(url: url); let metadata = try await asset.load(.commonMetadata)
        let genres = metadata.compactMap { $0.commonKey?.rawValue == "type" ? $0.stringValue : nil }.flatMap { $0.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) } }.filter { !$0.isEmpty }
        return EmbeddedMovieMetadata(title: stringValue(for: "title", in: metadata), creationDate: stringValue(for: "creationDate", in: metadata), overview: stringValue(for: "description", in: metadata), genres: Array(Set(genres)).sorted(), studio: stringValue(for: "publisher", in: metadata), artist: stringValue(for: "artist", in: metadata) ?? stringValue(for: "creator", in: metadata), artwork: metadata.first { $0.commonKey?.rawValue == "artwork" }?.dataValue)
    }

    private static func stringValue(for key: String, in metadata: [AVMetadataItem]) -> String? {
        metadata.first { $0.commonKey?.rawValue == key }?.stringValue
    }

    /// FNV-1a is used only to compare local audit evidence, not as an
    /// integrity/security checksum. It avoids retaining poster bytes for every
    /// movie in a saved audit.
    public static func artworkDigest(_ data: Data) -> UInt64 {
        data.reduce(1_469_598_103_934_665_603) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }

    @MainActor
    private static func languages(for tracks: [AVAssetTrack], type: AVMediaType) async throws -> [String] {
        var values = Set<String>()
        for track in tracks where track.mediaType == type {
            if let language = try? await track.load(.extendedLanguageTag), !language.isEmpty { values.insert(language) }
            else if let language = try? await track.load(.languageCode), !language.isEmpty { values.insert(language) }
        }
        return values.sorted()
    }
}
