import Foundation
import Security

/// Keychain persistence for the last successful license validation snapshot.
public struct LicenseSnapshotStore: Sendable {
    public static let shared = LicenseSnapshotStore()

    private let service = "dev.nuotsu.Studiofront.license"
    private let account = "validationSnapshot"

    public init() {}

    public func load() throws -> LicenseValidationSnapshot? {
        switch KeychainPassword.readData(service: service, account: account) {
        case .missing:
            return nil
        case .value(let data):
            return try JSONDecoder().decode(LicenseValidationSnapshot.self, from: data)
        case .inaccessible:
            throw LicenseError.transport("Couldn’t read the saved license snapshot.")
        }
    }

    public func save(_ snapshot: LicenseValidationSnapshot) throws {
        try delete()
        let data = try JSONEncoder().encode(snapshot)
        let status = KeychainPassword.addData(data, service: service, account: account)
        guard status == errSecSuccess else {
            throw LicenseError.transport("Couldn’t save the license snapshot.")
        }
    }

    public func delete() throws {
        let status = KeychainPassword.delete(service: service, account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseError.transport("Couldn’t clear the license snapshot.")
        }
    }
}
