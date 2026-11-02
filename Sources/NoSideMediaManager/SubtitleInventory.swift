import Foundation

public struct SubtitleInventory: Sendable, Equatable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public enum Source: String, Sendable, Equatable { case embedded, external }
        public let id: String; public let language: String; public let source: Source; public let sdh: Bool; public let forced: Bool
        public init(id: String, language: String, source: Source, sdh: Bool = false, forced: Bool = false) { self.id = id; self.language = language; self.source = source; self.sdh = sdh; self.forced = forced }
    }
    public let entries: [Entry]
    public var hasEnglish: Bool { entries.contains { $0.language == "en" || $0.language == "eng" } }
    public var hasFrench: Bool { entries.contains { $0.language == "fr" || $0.language == "fra" || $0.language == "fre" } }
    public var needsEnglishOrFrench: Bool { !hasEnglish || !hasFrench }

    public static func inspect(video: URL, embeddedLanguages: [String], fileManager: FileManager = .default) -> SubtitleInventory {
        let stem = video.deletingPathExtension().lastPathComponent
        let folder = video.deletingLastPathComponent()
        let embedded = embeddedLanguages.enumerated().map { Entry(id: "embedded-\($0.offset)", language: normalized($0.element), source: .embedded) }
        let sidecars = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let external = sidecars.filter { $0.lastPathComponent.hasPrefix(stem + ".") && ["srt", "ass", "ssa", "sub", "vtt"].contains($0.pathExtension.lowercased()) }.map { file -> Entry in
            let labels = file.deletingPathExtension().lastPathComponent.split(separator: ".").dropFirst().map(String.init)
            let lower = labels.map { $0.lowercased() }
            let language = lower.first(where: { ["en", "eng", "fr", "fra", "fre"].contains($0) }) ?? "unknown"
            return Entry(id: file.path, language: language, source: .external, sdh: lower.contains(where: { $0 == "sdh" || $0 == "cc" || $0 == "hi" }), forced: lower.contains("forced"))
        }
        return SubtitleInventory(entries: embedded + external)
    }
    private static func normalized(_ raw: String) -> String { let value = raw.lowercased(); return ["english": "en", "french": "fr", "und": "unknown"][value] ?? value }
}
