import Foundation
import Security

/// Reads optional local TVDB credentials from the logged-in user's Keychain.
/// Values are never written to plans, job bundles, logs, or source control.
public enum TVDBCredentialStore {
    private static let lock = NSLock()
    /// Keychain access can present UI on older Macs. Hold an unchanged value in
    /// memory for this app session so opening Settings, searching, and starting
    /// Companion do not repeatedly ask the user to authenticate.
    nonisolated(unsafe) private static var cache = [String: String]()
    nonisolated(unsafe) private static var loaded = Set<String>()

    public static func value(named name: String) -> String? {
        lock.lock()
        if loaded.contains(name) {
            let value = cache[name] ?? ""
            lock.unlock()
            return value.isEmpty ? nil : value
        }
        lock.unlock()
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "NoSideMediaManager.\(name)",
            kSecAttrAccount: NSUserName(),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let value: String
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data,
           let decoded = String(data: data, encoding: .utf8) {
            value = decoded
        } else {
            value = ""
        }
        lock.lock(); cache[name] = value; loaded.insert(name); lock.unlock()
        return value.isEmpty ? nil : value
    }
    public static func set(_ value: String, named name: String) throws {
        lock.lock()
        let unchanged = loaded.contains(name) && cache[name] == value
        lock.unlock()
        if unchanged { return }
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "NoSideMediaManager.\(name)", kSecAttrAccount: NSUserName()]
        let data = Data(value.utf8)
        let status = SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
            ? SecItemUpdate(query as CFDictionary, [kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock] as CFDictionary)
            : SecItemAdd((query.merging([kSecValueData: data, kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock]) { _, new in new }) as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil) }
        lock.lock(); cache[name] = value; loaded.insert(name); lock.unlock()
    }

    /// TVDB access tokens are credentials too: keep the short-lived session in
    /// Keychain, never in preferences or a package.  The API does not expose a
    /// reliable expiry in every login response, so MMM uses a deliberately
    /// conservative six-hour lifetime and obtains a fresh token afterwards.
    public static func cachedTVDBSession(for apiKey: String, now: Date = Date()) -> String? {
        guard let value = value(named: "TVDB_SESSION"),
              let record = try? JSONDecoder().decode(TVDBSessionRecord.self, from: Data(value.utf8)),
              record.apiKey == apiKey, record.expiresAt > now else { return nil }
        return record.token
    }
    public static func storeTVDBSession(_ token: String, for apiKey: String, now: Date = Date()) throws {
        let record = TVDBSessionRecord(apiKey: apiKey, token: token, expiresAt: now.addingTimeInterval(6 * 60 * 60))
        let data = try JSONEncoder().encode(record)
        try set(String(decoding: data, as: UTF8.self), named: "TVDB_SESSION")
    }
}

struct TVDBSessionRecord: Codable, Equatable {
    let apiKey: String
    let token: String
    let expiresAt: Date
}
