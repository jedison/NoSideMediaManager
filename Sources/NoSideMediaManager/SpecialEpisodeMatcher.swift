import Foundation

/// A conservative, title-led suggestion engine for specials which have been
/// released locally with regular-season episode numbers. Suggestions are only
/// candidates: callers must explicitly approve them before a mapping changes.
public struct SpecialEpisodeProposal: Sendable, Equatable, Identifiable {
    public let local: LocalEpisodeFile
    public let canonical: TVEpisode?
    public let evidence: String
    public let confidence: Double
    public let isAmbiguous: Bool
    public var id: URL { local.url }
}

public enum SpecialEpisodeMatcher {
    public static func propose(unmatched locals: [LocalEpisodeFile], canonicalEpisodes: [TVEpisode]) -> [SpecialEpisodeProposal] {
        let specials = canonicalEpisodes.filter { $0.season == 0 }
        var proposals = locals.map { local -> SpecialEpisodeProposal in
            let localTitle = titleEvidence(for: local)
            let ranked = specials.map { episode in (episode, score(localTitle, episode.title)) }.sorted { $0.1 > $1.1 }
            guard let best = ranked.first, best.1 >= 0.72 else {
                return .init(local: local, canonical: nil, evidence: "No strong Season 0 title match", confidence: 0, isAmbiguous: false)
            }
            let tied = ranked.dropFirst().first.map { abs($0.1 - best.1) < 0.08 } ?? false
            return .init(local: local, canonical: best.0, evidence: "Title evidence: \(localTitle)", confidence: best.1, isAmbiguous: tied)
        }
        let duplicateTargets = Dictionary(grouping: proposals.compactMap { proposal in proposal.canonical.map { ($0.tvdbID, proposal.local.url) } }, by: \.0)
            .filter { $0.value.count > 1 }.map(\.key)
        proposals = proposals.map { proposal in
            guard let canonical = proposal.canonical else { return proposal }
            return .init(local: proposal.local, canonical: canonical, evidence: proposal.evidence, confidence: proposal.confidence, isAmbiguous: proposal.isAmbiguous || duplicateTargets.contains(canonical.tvdbID))
        }
        return proposals.sorted { $0.local.url.path < $1.local.url.path }
    }

    /// Produces only safe bulk approvals. Existing explicit choices are never
    /// replaced; ambiguous or duplicate-target proposals remain manual.
    public static func bulkApprovals(proposals: [SpecialEpisodeProposal], existing: [URL: Int]) -> [URL: Int] {
        Dictionary(uniqueKeysWithValues: proposals.compactMap { proposal in
            guard existing[proposal.local.url] == nil, !proposal.isAmbiguous, let episode = proposal.canonical else { return nil }
            return (proposal.local.url, episode.tvdbID)
        })
    }

    private static func titleEvidence(for local: LocalEpisodeFile) -> String {
        local.metadataTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? (local.url.deletingPathExtension().lastPathComponent)
    }
    private static func score(_ local: String, _ canonical: String) -> Double {
        let a = tokens(local), b = tokens(canonical)
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return 1 }
        let overlap = a.intersection(b).count
        return Double(overlap) / Double(a.union(b).count)
    }
    private static func tokens(_ value: String) -> Set<String> {
        let stripped = value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"(?i)\b(the|great|british|bake|off|gbbo|series|season|episode|s\d{1,3}e\d{1,3})\b"#, with: "", options: .regularExpression)
        return Set(stripped.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 1 }
            .map { $0.hasSuffix("s") && $0.count > 3 ? String($0.dropLast()) : $0 })
    }
}

private extension String { var nilIfEmpty: String? { isEmpty ? nil : self } }
