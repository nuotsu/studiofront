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
        switch KeychainPassword.readData(service: service, account: account) {
        case .missing:
            return nil
        case .value(let data):
            return String(data: data, encoding: .utf8)
        case .inaccessible:
            throw LicenseError.transport("Couldn’t read the saved license.")
        }
    }

    private func add(value: String, account: String) throws {
        let status = KeychainPassword.addData(Data(value.utf8), service: service, account: account)
        guard status == errSecSuccess else {
            throw LicenseError.transport("Couldn’t save the license securely.")
        }
    }

    private func delete(account: String) throws {
        let status = KeychainPassword.delete(service: service, account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseError.transport("Couldn’t clear the saved license.")
        }
    }
}
