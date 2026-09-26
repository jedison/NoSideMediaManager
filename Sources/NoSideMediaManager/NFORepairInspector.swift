import Foundation

public struct NFOFieldDifference: Sendable, Equatable, Identifiable {
    public let field: String
    public let localValue: String?
    public let canonicalValue: String?
    public var id: String { field }
}

public enum NFORepairInspector {
    public static func differences(at url: URL, comparedTo episode: TVEpisode) throws -> [NFOFieldDifference] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let document = try XMLDocument(contentsOf: url, options: [])
        var values = [String: String?]()
        for field in ["title", "plot", "aired", "season", "episode"] { values[field] = try document.nodes(forXPath: "//\(field)").first?.stringValue }
        let expected = ["title": episode.title, "plot": episode.overview, "aired": episode.aired, "season": String(episode.season), "episode": String(episode.number)]
        return expected.compactMap { key, value in values[key] == value ? nil : NFOFieldDifference(field: key, localValue: values[key] ?? nil, canonicalValue: value) }.sorted { $0.field < $1.field }
    }
}
