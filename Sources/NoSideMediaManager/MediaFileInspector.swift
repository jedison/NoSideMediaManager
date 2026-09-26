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
}

public enum MediaFileInspector {
    private static let videoExtensions: Set<String> = ["m4v", "mkv", "mp4", "avi", "mov"]

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
        return EmbeddedMediaInfo(
            fileName: url.lastPathComponent,
            title: stringValue(for: "title", in: metadata),
            creationDate: stringValue(for: "creationDate", in: metadata),
            durationSeconds: duration.isNumeric ? duration.seconds : nil,
            width: size.map { Int($0.width.rounded()) },
            height: size.map { Int($0.height.rounded()) },
            audioLanguages: try await languages(for: tracks, type: .audio),
            subtitleLanguages: try await languages(for: tracks, type: .subtitle),
            hasEmbeddedArtwork: metadata.contains { $0.commonKey?.rawValue == "artwork" && $0.dataValue != nil }
        )
    }

    private static func stringValue(for key: String, in metadata: [AVMetadataItem]) -> String? {
        metadata.first { $0.commonKey?.rawValue == key }?.stringValue
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
