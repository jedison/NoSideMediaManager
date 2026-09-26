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
}
