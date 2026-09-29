import Foundation
import Network

/// Deliberately small authenticated HTTP transport for the MMM Mac app. It is
/// not a file server: it exposes authenticated inspection plus operations on
/// already-frozen packages only. It never accepts arbitrary file operations.
public final class CompanionHTTPServer: @unchecked Sendable {
    public enum ServerError: LocalizedError { case invalidPort; public var errorDescription: String? { "The Companion port is invalid." } }
    private let service: CompanionJobService; private let token: String; private var listener: NWListener?
    public private(set) var port: UInt16?
    public init(service: CompanionJobService, token: String) { self.service = service; self.token = token }
    public func start(port: UInt16, lanVisible: Bool) throws {
        guard listener == nil else { return }; guard port > 0 else { throw ServerError.invalidPort }
        let parameters = NWParameters.tcp; parameters.requiredLocalEndpoint = lanVisible ? .hostPort(host: .ipv4(.any), port: NWEndpoint.Port(rawValue: port)!) : .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: port)!)
        let listener = try NWListener(using: parameters); self.listener = listener; self.port = port
        listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }; listener.start(queue: .global(qos: .userInitiated))
    }
    public func stop() { listener?.cancel(); listener = nil; port = nil }
    private func receive(_ connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else { connection.cancel(); return }
            Task { let response = await self.route(request); connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in connection.cancel() }) }
        }
    }
    private func route(_ raw: String) async -> String {
        let requestParts = raw.components(separatedBy: "\r\n\r\n"); let lines = (requestParts.first ?? raw).components(separatedBy: "\r\n"); let body = requestParts.dropFirst().joined(separator: "\r\n\r\n"); guard let first = lines.first?.split(separator: " "), first.count >= 2 else { return response(400, ["error": "Malformed request"]) }
        let method = String(first[0]); let target = String(first[1]); let components = URLComponents(string: "http://microMM\(target)"); let path = components?.path ?? target; let headers = Dictionary(uniqueKeysWithValues: lines.dropFirst().compactMap { line -> (String, String)? in guard let index = line.firstIndex(of: ":") else { return nil }; return (line[..<index].lowercased(), line[line.index(after: index)...].trimmingCharacters(in: .whitespaces)) })
        guard headers["authorization"] == "Bearer \(token)" else { return response(401, ["error": "Unauthorized"]) }
        if method == "GET", path == "/v1/health" { return response(200, await service.serverInfo()) }
        if method == "GET", path == "/v1/jobs" { return response(200, await service.jobs()) }
        if method == "POST", path == "/v1/audit/movies" { return response(200, await service.startMovieAudit()) }
        if method == "GET", path == "/v1/audit/movies" { return response(200, await service.movieAuditStatus()) }
        if method == "GET", path == "/v1/audit/tv/folders" { return response(200, await service.tvFolders()) }
        if method == "GET", path == "/v1/audit/tv" { guard let folder = components?.queryItems?.first(where: { $0.name == "folder" })?.value else { return response(400, ["error": "Choose a TV folder first."]) }; do { return response(200, try await service.tvAudit(folder: folder)) } catch { return response(400, ["error": error.localizedDescription]) } }
        if method == "POST", path == "/v1/audit/movies/preservation-package" { guard let request = try? JSONDecoder().decode(CompanionMoviePackageRequest.self, from: Data(body.utf8)) else { return response(400, ["error": "A selected video list is required."]) }; do { return response(200, try await service.freezePreservationPackage(videoPaths: request.videoPaths)) } catch { return response(400, ["error": error.localizedDescription]) } }
        if method == "POST", path == "/v1/audit/movies/sidecar-package" { guard let request = try? JSONDecoder().decode(CompanionMoviePackageRequest.self, from: Data(body.utf8)) else { return response(400, ["error": "A selected video list is required."]) }; do { return response(200, try await service.freezeSidecarPackage(videoPaths: request.videoPaths)) } catch { return response(400, ["error": error.localizedDescription]) } }
        if method == "GET", path == "/v1/search/tv" { guard let query = components?.queryItems?.first(where: { $0.name == "query" })?.value?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty else { return response(400, ["error": "A TV search query is required."]) }; do { return response(200, try await service.searchTV(query: query)) } catch { return response(400, ["error": error.localizedDescription]) } }
        let parts = path.split(separator: "/").map(String.init)
        guard method == "POST", parts.count == 4, parts[0] == "v1", parts[1] == "jobs", let operation = CompanionOperation(rawValue: parts[3]) else { return response(404, ["error": "Not found"]) }
        let jobID = parts[2]
        if operation == .apply, headers["x-mmm-confirm"] != jobID { return response(409, ["error": "Apply requires X-MMM-Confirm equal to the job ID."]) }
        do { return response(200, try await service.run(jobID: jobID, operation: operation)) } catch { return response(400, ["error": error.localizedDescription]) }
    }
    private func response<T: Encodable>(_ status: Int, _ payload: T) -> String {
        let data = (try? JSONEncoder().encode(payload)) ?? Data("{\"error\":\"Encoding failure\"}".utf8)
        return "HTTP/1.1 \(status) \(status == 200 ? "OK" : "Error")\r\nContent-Type: application/json\r\nContent-Length: \(data.count)\r\nConnection: close\r\n\r\n" + String(decoding: data, as: UTF8.self)
    }
}
