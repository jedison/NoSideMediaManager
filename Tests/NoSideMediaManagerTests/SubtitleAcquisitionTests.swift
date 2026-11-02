import Foundation
import Testing
@testable import NoSideMediaManager

@Test func reviewedSubtitlePackageStagesEnglishAndRefusesExistingSidecar() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); let video = root.appendingPathComponent("Season 01/Show.mkv"); let bundle = root.appendingPathComponent("job")
    try FileManager.default.createDirectory(at: video.deletingLastPathComponent(), withIntermediateDirectories: true); try Data().write(to: video); defer { try? FileManager.default.removeItem(at: root) }
    let candidate = SubtitleCandidate(id: "1", provider: "mock", language: "en", episodeTitle: "Cake", season: 1, episode: 1, format: "srt")
    _ = try PortableJobBundle.createSubtitles(at: bundle, libraryRoot: root, items: [.init(video: video, candidate: candidate, data: Data("1\\n00:00:00,000 --> 00:00:01,000\\nHello".utf8))])
    #expect(FileManager.default.fileExists(atPath: bundle.appendingPathComponent("generated/Season 01/Show.en.srt").path))
    try Data("old".utf8).write(to: video.deletingPathExtension().appendingPathExtension("en.srt"))
    var collision = false
    do { _ = try PortableJobBundle.createSubtitles(at: root.appendingPathComponent("job2"), libraryRoot: root, items: [.init(video: video, candidate: candidate, data: Data("1\\n00:00:00,000 --> 00:00:01,000\\nHello".utf8))]) } catch SubtitleAcquisitionError.destinationExists { collision = true }
    #expect(collision)
}

@Test func subtitleAcquisitionRejectsCorruptSRT() {
    let candidate = SubtitleCandidate(id: "1", provider: "mock", language: "fr", episodeTitle: "Cake", season: 1, episode: 1, format: "srt")
    #expect(throws: SubtitleAcquisitionError.invalidContent) { _ = try SubtitleAcquisition.stagedURL(for: .init(video: URL(fileURLWithPath: "/tmp/a.mkv"), candidate: candidate, data: Data("not subtitles".utf8))) }
}
