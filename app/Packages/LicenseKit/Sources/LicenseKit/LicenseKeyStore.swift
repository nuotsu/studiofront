import Foundation
import Security

/// Keychain-only license storage. Never UserDefaults, SwiftData, or a plist.
public struct LicenseKeyStore: Sendable {
    public static let shared = LicenseKeyStore()

    private let service = "dev.nuotsu.Studiofront.license"
    private let keyAccount = "licenseKey"
    private let instanceIDAccount = "instanceId"

    public init() {}

    public func loadKey() throws -> String? {
        try load(account: keyAccount)
    }

    public func loadInstanceID() throws -> String? {
        try load(account: instanceIDAccount)
    }

    public func save(key: String, instanceID: String) throws {
        try delete()
        try add(value: key, account: keyAccount)
        try add(value: instanceID, account: instanceIDAccount)
    }

    public func delete() throws {
        try delete(account: keyAccount)
        try delete(account: instanceIDAccount)
    }

    private func load(account: String) throws -> String? {
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
            throw LicenseError.transport("Couldn’t read the saved license.")
        }
        return String(data: data, encoding: .utf8)
    }

    private func add(value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseError.transport("Couldn’t save the license securely.")
        }
    }

    private func delete(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseError.transport("Couldn’t clear the saved license.")
        }
    }
}
