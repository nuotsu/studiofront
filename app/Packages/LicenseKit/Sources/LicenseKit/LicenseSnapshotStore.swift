import Foundation
import Security

/// Keychain persistence for the last successful license validation snapshot.
public struct LicenseSnapshotStore: Sendable {
    public static let shared = LicenseSnapshotStore()

    private let service = "dev.nuotsu.Studiofront.license"
    private let account = "validationSnapshot"

    public init() {}

    public func load() throws -> LicenseValidationSnapshot? {
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
            throw LicenseError.transport("Couldn’t read the saved license snapshot.")
        }
        return try JSONDecoder().decode(LicenseValidationSnapshot.self, from: data)
    }

    public func save(_ snapshot: LicenseValidationSnapshot) throws {
        try delete()
        let data = try JSONEncoder().encode(snapshot)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseError.transport("Couldn’t save the license snapshot.")
        }
    }

    public func delete() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseError.transport("Couldn’t clear the license snapshot.")
        }
    }
}
