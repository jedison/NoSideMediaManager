import Foundation

public enum OpenSubtitlesError: LocalizedError, Equatable { case unauthorized, rateLimited, malformedResponse, unsafeDownloadURL, network(String)
    public var errorDescription: String? { switch self { case .unauthorized: "OpenSubtitles rejected the API key."; case .rateLimited: "OpenSubtitles download quota or rate limit was reached."; case .malformedResponse: "OpenSubtitles returned an incomplete response."; case .unsafeDownloadURL: "OpenSubtitles returned an unsafe download URL."; case .network(let message): message } }
}
public struct OpenSubtitlesClient: SubtitleSearchProvider {
    public let apiKey: String; public let session: URLSession; public let baseURL: URL
    public let providerName = "OpenSubtitles.com"
    public init(apiKey: String, session: URLSession = .shared, baseURL: URL = URL(string: "https://api.opensubtitles.com/api/v1")!) { self.apiKey = apiKey; self.session = session; self.baseURL = baseURL }
    public func search(_ request: SubtitleSearchRequest) async throws -> [SubtitleCandidate] {
        var components = URLComponents(url: baseURL.appendingPathComponent("subtitles"), resolvingAgainstBaseURL: false)!; components.queryItems = [URLQueryItem(name: "episode_number", value: String(request.episode.number)), URLQueryItem(name: "languages", value: request.languages.joined(separator: ",")), URLQueryItem(name: "query", value: request.seriesTitle ?? request.episode.title), URLQueryItem(name: "season_number", value: String(request.episode.season))]
        let (data, _) = try await send(URLRequest(url: components.url!)); let object = try json(data); let rows = object["data"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let attributes = row["attributes"] as? [String: Any], let files = attributes["files"] as? [[String: Any]], let file = files.first, let id = file["file_id"] as? Int else { return nil }
            let details = attributes["feature_details"] as? [String: Any]; let title = (details?["episode_name"] as? String) ?? (details?["movie_name"] as? String) ?? ""
            return SubtitleCandidate(id: String(id), provider: providerName, language: (attributes["language"] as? String) ?? "unknown", episodeTitle: title, season: (details?["season_number"] as? Int) ?? -1, episode: (details?["episode_number"] as? Int) ?? -1, format: (attributes["format"] as? String) ?? "srt", release: attributes["release"] as? String)
        }
    }
    public func download(_ candidate: SubtitleCandidate) async throws -> Data {
        guard let fileID = Int(candidate.id) else { throw OpenSubtitlesError.malformedResponse }
        var request = URLRequest(url: baseURL.appendingPathComponent("download")); request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: ["file_id": fileID])
        let (data, _) = try await send(request); let object = try json(data); guard let link = object["link"] as? String, let url = URL(string: link), url.scheme == "https" else { throw OpenSubtitlesError.unsafeDownloadURL }
        let (subtitle, response) = try await session.data(from: url); guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !subtitle.isEmpty, subtitle.count <= 5_000_000 else { throw OpenSubtitlesError.malformedResponse }; return subtitle
    }
    private func send(_ input: URLRequest) async throws -> (Data, HTTPURLResponse) { var request = input; request.setValue(apiKey, forHTTPHeaderField: "Api-Key"); request.setValue("microMM/0.4", forHTTPHeaderField: "User-Agent"); do { let (data, response) = try await session.data(for: request); guard let http = response as? HTTPURLResponse else { throw OpenSubtitlesError.malformedResponse }; if http.statusCode == 401 || http.statusCode == 403 { throw OpenSubtitlesError.unauthorized }; if http.statusCode == 429 { throw OpenSubtitlesError.rateLimited }; guard (200..<300).contains(http.statusCode) else { throw OpenSubtitlesError.network("OpenSubtitles request failed (HTTP \(http.statusCode)).") }; return (data, http) } catch let error as OpenSubtitlesError { throw error } catch { throw OpenSubtitlesError.network(error.localizedDescription) } }
    private func json(_ data: Data) throws -> [String: Any] { guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw OpenSubtitlesError.malformedResponse }; return object }
}
