import Foundation
import Security

/// Keychain-only token storage. Never UserDefaults, SwiftData, or a plist.
public struct TokenStore: Sendable {
    public static let shared = TokenStore()

    private let service = "dev.nuotsu.Studiofront.sanity"
    private let account = "authToken"
    private let sourceDefaultsKey = "sanity.tokenSource"

    public init() {}

    public func load() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw SanityAuthError.unreadable("Couldn’t read the saved token.")
        }
        return String(data: data, encoding: .utf8)
    }

    public func source() -> TokenSource? {
        TokenSource(rawValue: UserDefaults.standard.string(forKey: sourceDefaultsKey) ?? "")
    }

    public func save(token: String, source: TokenSource) throws {
        try delete()
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SanityAuthError.unreadable("Couldn’t save the token securely.")
        }
        UserDefaults.standard.set(source.rawValue, forKey: sourceDefaultsKey)
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SanityAuthError.unreadable("Couldn’t clear the saved token.")
        }
        UserDefaults.standard.removeObject(forKey: sourceDefaultsKey)
    }
}
