import Foundation

public struct ReviewedSubtitleDownload: Sendable, Equatable {
    public let video: URL; public let destinationVideo: URL; public let candidate: SubtitleCandidate; public let data: Data
    public init(video: URL, destinationVideo: URL? = nil, candidate: SubtitleCandidate, data: Data) { self.video = video; self.destinationVideo = destinationVideo ?? video; self.candidate = candidate; self.data = data }
}
public enum SubtitleAcquisitionError: LocalizedError, Equatable { case unsupportedFormat, invalidContent, destinationExists(URL)
    public var errorDescription: String? { switch self { case .unsupportedFormat: "The selected subtitle has an unsupported format."; case .invalidContent: "The downloaded subtitle is empty or is not valid subtitle text."; case .destinationExists(let url): "A subtitle already exists at \(url.path); MMM will not replace it automatically." } }
}
public enum SubtitleAcquisition {
    public static func stagedURL(for item: ReviewedSubtitleDownload) throws -> URL {
        let format = item.candidate.format.lowercased(); guard ["srt", "ass", "ssa", "vtt"].contains(format) else { throw SubtitleAcquisitionError.unsupportedFormat }
        guard !item.data.isEmpty, (format != "srt" || String(decoding: item.data, as: UTF8.self).contains("-->")) else { throw SubtitleAcquisitionError.invalidContent }
        let language = item.candidate.language.lowercased()
        return item.destinationVideo.deletingPathExtension().appendingPathExtension(language).appendingPathExtension(format)
    }
}
