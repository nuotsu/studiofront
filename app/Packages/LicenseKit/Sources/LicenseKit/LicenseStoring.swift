import Foundation

/// Keychain (or in-memory) storage for the customer's license key + instance id.
public protocol LicenseKeyStoring: Sendable {
    func loadKey() throws -> String?
    func loadInstanceID() throws -> String?
    func save(key: String, instanceID: String) throws
    func delete() throws
}

/// Keychain (or in-memory) storage for the 7-day trial start date.
public protocol TrialStoring: Sendable {
    func loadStartDate() throws -> Date?
    func recordStartIfNeeded(now: Date) throws
}

/// Keychain (or in-memory) storage for the last successful validation snapshot.
public protocol LicenseSnapshotStoring: Sendable {
    func load() throws -> LicenseValidationSnapshot?
    func save(_ snapshot: LicenseValidationSnapshot) throws
    func delete() throws
}

/// Lemon License API surface used by `LicenseService` (real client or test double).
public protocol LicenseNetworking: Sendable {
    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation
    func validate(licenseKey: String, instanceID: String?) async throws -> LicenseValidation
    func deactivate(licenseKey: String, instanceID: String) async throws
}

extension LicenseKeyStore: LicenseKeyStoring {}
extension TrialStore: TrialStoring {}
extension LicenseSnapshotStore: LicenseSnapshotStoring {}
extension LicenseClient: LicenseNetworking {}
