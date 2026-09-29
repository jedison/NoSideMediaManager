import Foundation

enum CompanionClientError: LocalizedError { case invalidURL, server(String); var errorDescription: String? { switch self { case .invalidURL: "Enter a valid Companion address."; case .server(let message): message } } }

struct CompanionClient {
    let host: String; let port: Int; let token: String
    private func request(path: String, method: String = "GET", confirm: String? = nil, body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: "http://\(host):\(port)\(path)") else { throw CompanionClientError.invalidURL }
        var request = URLRequest(url: url); request.httpMethod = method; request.timeoutInterval = 60; request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization"); if let confirm { request.setValue(confirm, forHTTPHeaderField: "X-MMM-Confirm") }; if let body { request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = body }; return request
    }
    func health() async throws -> CompanionServerInfo { try await perform(try request(path: "/v1/health")) }
    func jobs() async throws -> [CompanionJob] { try await perform(try request(path: "/v1/jobs")) }
    func movieAudit() async throws -> CompanionMovieAuditReport { try await perform(try request(path: "/v1/audit/movies")) }
    func tvFolders() async throws -> [CompanionTVFolder] { try await perform(try request(path: "/v1/audit/tv/folders")) }
    func tvAudit(folder: String) async throws -> CompanionTVAuditReport { let folder = folder.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? folder; return try await perform(try request(path: "/v1/audit/tv?folder=\(folder)")) }
    func freezeMoviePackage(_ kind: String, videoPaths: [String]) async throws -> CompanionJob { let body = try JSONEncoder().encode(CompanionMoviePackageRequest(videoPaths: videoPaths)); return try await perform(try request(path: "/v1/audit/movies/\(kind)-package", method: "POST", body: body)) }
    func searchTV(_ query: String) async throws -> [TVSeriesSearchResult] { let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query; return try await perform(try request(path: "/v1/search/tv?query=\(encoded)")) }
    func run(_ job: CompanionJob, operation: CompanionOperation) async throws -> CompanionOperationResult { try await perform(try request(path: "/v1/jobs/\(job.id)/\(operation.rawValue)", method: "POST", confirm: operation == .apply ? job.id : nil)) }
    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T { let (data, response) = try await URLSession.shared.data(for: request); guard let http = response as? HTTPURLResponse else { throw CompanionClientError.server("No response from Companion.") }; guard (200...299).contains(http.statusCode) else { let message = (try? JSONDecoder().decode([String: String].self, from: data)["error"]) ?? "Companion request failed (HTTP \(http.statusCode))."; throw CompanionClientError.server(message) }; return try JSONDecoder().decode(T.self, from: data) }
}

@MainActor final class CompanionSession: ObservableObject {
    @Published var host = UserDefaults.standard.string(forKey: "companionHost") ?? ""
    @Published var port = UserDefaults.standard.integer(forKey: "companionPort") == 0 ? 8347 : UserDefaults.standard.integer(forKey: "companionPort")
    @Published var token = UserDefaults.standard.string(forKey: "companionToken") ?? ""
    @Published var server: CompanionServerInfo?; @Published var jobs = [CompanionJob](); @Published var status = "Pair with microMM on the old MBA."; @Published var isLoading = false
    var client: CompanionClient {
        CompanionClient(
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            token: token.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
    func save() {
        host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        token = token.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(host, forKey: "companionHost")
        UserDefaults.standard.set(port, forKey: "companionPort")
        UserDefaults.standard.set(token, forKey: "companionToken")
    }
    func refresh() async { isLoading = true; defer { isLoading = false }; do { server = try await client.health(); jobs = try await client.jobs(); status = "Connected · \(jobs.count) frozen jobs" } catch { status = error.localizedDescription } }
}
