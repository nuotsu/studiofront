import Foundation
import LicenseKit

/// In-memory doubles for LicenseKit unit tests.
final class InMemoryLicenseKeyStore: LicenseKeyStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var key: String?
    private var instanceID: String?

    func loadKey() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return key
    }

    func loadInstanceID() throws -> String? {
        lock.lock(); defer { lock.unlock() }
        return instanceID
    }

    func save(key: String, instanceID: String) throws {
        lock.lock(); defer { lock.unlock() }
        self.key = key
        self.instanceID = instanceID
    }

    func delete() throws {
        lock.lock(); defer { lock.unlock() }
        key = nil
        instanceID = nil
    }
}

final class InMemoryTrialStore: TrialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var start: Date?

    init(start: Date? = nil) {
        self.start = start
    }

    func loadStartDate() throws -> Date? {
        lock.lock(); defer { lock.unlock() }
        return start
    }

    func recordStartIfNeeded(now: Date) throws {
        lock.lock(); defer { lock.unlock() }
        if start == nil { start = now }
    }
}

final class InMemorySnapshotStore: LicenseSnapshotStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshot: LicenseValidationSnapshot?

    init(snapshot: LicenseValidationSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func load() throws -> LicenseValidationSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshot
    }

    func save(_ snapshot: LicenseValidationSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        self.snapshot = snapshot
    }

    func delete() throws {
        lock.lock(); defer { lock.unlock() }
        snapshot = nil
    }
}

actor MockLicenseClient: LicenseNetworking {
    var validateResult: Result<LicenseValidation, Error> = .failure(LicenseError.transport("offline"))
    var deactivateResult: Result<Void, Error> = .success(())
    var activateResult: Result<LicenseActivation, Error> = .failure(LicenseError.transport("offline"))
    private(set) var deactivateCallCount = 0

    func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        try activateResult.get()
    }

    func validate(licenseKey: String, instanceID: String?) async throws -> LicenseValidation {
        try validateResult.get()
    }

    func deactivate(licenseKey: String, instanceID: String) async throws {
        deactivateCallCount += 1
        try deactivateResult.get()
    }
}
