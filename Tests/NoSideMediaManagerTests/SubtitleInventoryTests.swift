import Foundation
import Testing
@testable import NoSideMediaManager

@Test func subtitleInventoryCombinesEmbeddedAndLanguageNamedSidecars() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: root) }
    let video = root.appendingPathComponent("GBBO S01E01.mkv"); FileManager.default.createFile(atPath: video.path, contents: Data())
    FileManager.default.createFile(atPath: root.appendingPathComponent("GBBO S01E01.fr.sdh.srt").path, contents: Data())
    FileManager.default.createFile(atPath: root.appendingPathComponent("GBBO S01E01.en.forced.ass").path, contents: Data())
    let inventory = SubtitleInventory.inspect(video: video, embeddedLanguages: ["English", "und"])
    #expect(inventory.hasEnglish); #expect(inventory.hasFrench); #expect(!inventory.needsEnglishOrFrench)
    #expect(inventory.entries.contains { $0.source == .external && $0.language == "fr" && $0.sdh })
    #expect(inventory.entries.contains { $0.source == .external && $0.language == "en" && $0.forced })
}
