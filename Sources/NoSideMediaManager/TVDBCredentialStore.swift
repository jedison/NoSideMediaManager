import Foundation
import Security

/// Reads optional local TVDB credentials from the logged-in user's Keychain.
/// Values are never written to plans, job bundles, logs, or source control.
public enum TVDBCredentialStore {
    private static let lock = NSLock()
    /// Keychain access can present UI on older Macs. Hold an unchanged value in
    /// memory for this app session so opening Settings, searching, and starting
    /// Companion do not repeatedly ask the user to authenticate.
    private static var cache = [String: String]()
    private static var loaded = Set<String>()

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
        let value = (SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess && (result as? Data).flatMap { String(data: $0, encoding: .utf8) }) ?? ""
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
}
