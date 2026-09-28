import Foundation
import Security

/// Reads optional local TVDB credentials from the logged-in user's Keychain.
/// Values are never written to plans, job bundles, logs, or source control.
public enum TVDBCredentialStore {
    public static func value(named name: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "NoSideMediaManager.\(name)",
            kSecAttrAccount: NSUserName(),
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8), !value.isEmpty else { return nil }
        return value
    }
    public static func set(_ value: String, named name: String) throws {
        let query: [CFString: Any] = [kSecClass: kSecClassGenericPassword, kSecAttrService: "NoSideMediaManager.\(name)", kSecAttrAccount: NSUserName()]
        let data = Data(value.utf8)
        let status = SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
            ? SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
            : SecItemAdd((query.merging([kSecValueData: data]) { _, new in new }) as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil) }
    }
}
