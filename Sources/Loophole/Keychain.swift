import Foundation
import Security

/// Stores the Pi-hole password as a generic password in the login keychain.
enum Keychain {
    private static let service = "io.github.afefer.loophole"
    private static let account = "pihole-password"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func loadPassword() -> String {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    @discardableResult
    static func savePassword(_ password: String) -> Bool {
        SecItemDelete(baseQuery as CFDictionary)
        guard !password.isEmpty else { return true }
        var query = baseQuery
        query[kSecValueData as String] = Data(password.utf8)
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }
}
