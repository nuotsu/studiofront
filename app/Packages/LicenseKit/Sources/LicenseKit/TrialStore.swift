import Foundation
import Security

/// Keychain-only trial-start storage — deliberately not UserDefaults or a
/// plist, so it survives app deletion + reinstall and can't be reset just by
/// clearing app support files.
public struct TrialStore: Sendable {
    public static let shared = TrialStore()

    private let service = "dev.nuotsu.Studiofront.trial"
    private let account = "trialStartedAt"

    public init() {}

    public func loadStartDate() throws -> Date? {
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
        guard status == errSecSuccess, let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            throw LicenseError.transport("Couldn’t read the trial start date.")
        }
        return try? Date(string, strategy: Date.ISO8601FormatStyle())
    }

    /// No-ops if a start date already exists — first-launch-only write.
    public func recordStartIfNeeded(now: Date = Date()) throws {
        guard try loadStartDate() == nil else { return }
        let data = Data(now.ISO8601Format().utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseError.transport("Couldn’t record the trial start date.")
        }
    }
}
