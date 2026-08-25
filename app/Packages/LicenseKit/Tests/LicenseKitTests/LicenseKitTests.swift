import Foundation
import Testing
@testable import LicenseKit

@Suite("LicenseOfflinePolicy")
struct LicenseOfflinePolicyTests {
    @Test("expired snapshot stays expired")
    func expiredSnapshot() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = LicenseValidationSnapshot.expired(plan: .annual, at: now.addingTimeInterval(-60))
        let status = LicenseOfflinePolicy.resolve(snapshot: snapshot, now: now)
        #expect(status == .expired(plan: .annual))
    }

    @Test("past expiresAt downgrades to expired even inside grace")
    func pastExpiresAt() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = LicenseValidationSnapshot.licensed(
            plan: .monthly,
            expiresAt: now.addingTimeInterval(-1),
            at: now.addingTimeInterval(-60)
        )
        let status = LicenseOfflinePolicy.resolve(snapshot: snapshot, now: now)
        #expect(status == .expired(plan: .monthly))
    }

    @Test("licensed within grace stays unlimited")
    func withinGrace() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = LicenseValidationSnapshot.licensed(
            plan: .monthly,
            expiresAt: now.addingTimeInterval(30 * 24 * 60 * 60),
            at: now.addingTimeInterval(-60 * 60)
        )
        let status = LicenseOfflinePolicy.resolve(snapshot: snapshot, now: now)
        #expect(status == .licensed(plan: .monthly, expiresAt: snapshot.expiresAt))
    }

    @Test("licensed past grace drops to free caps")
    func pastGrace() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let snapshot = LicenseValidationSnapshot.licensed(
            plan: .monthly,
            expiresAt: now.addingTimeInterval(30 * 24 * 60 * 60),
            at: now.addingTimeInterval(-(LicenseOfflinePolicy.graceInterval + 1))
        )
        let status = LicenseOfflinePolicy.resolve(snapshot: snapshot, now: now)
        #expect(status == .free)
    }
}

@Suite("LicenseStatus entitlement")
struct LicenseStatusEntitlementTests {
    @Test("validating does not resolve an entitlement")
    func validating() {
        #expect(LicenseStatus.validating.entitlement == nil)
    }

    @Test("trial and licensed are unlimited")
    func unlimited() {
        #expect(LicenseStatus.trial(daysLeft: 3).entitlement == .unlimited)
        #expect(LicenseStatus.licensed(plan: .monthly, expiresAt: nil).entitlement == .unlimited)
    }

    @Test("free and expired use free caps")
    func freeCaps() {
        #expect(LicenseStatus.free.entitlement == .free)
        #expect(LicenseStatus.expired(plan: .annual).entitlement == .free)
        #expect(Entitlement.free.maxFavoriteProjects == 3)
        #expect(Entitlement.free.maxFavoriteOrganizations == 3)
    }
}

@Suite("LicenseService offline and deactivate")
@MainActor
struct LicenseServiceBehaviorTests {
    @Test("transport error keeps the key and applies snapshot grace")
    func transportKeepsKey() async {
        let keys = InMemoryLicenseKeyStore()
        try! keys.save(key: "test-key", instanceID: "instance-1")
        let snapshots = InMemorySnapshotStore(
            snapshot: .licensed(
                plan: .monthly,
                expiresAt: Date().addingTimeInterval(30 * 24 * 60 * 60),
                at: Date().addingTimeInterval(-60)
            )
        )
        let client = MockLicenseClient()
        await client.setValidateFailure(.transport("offline"))

        let service = LicenseService(
            client: client,
            licenseStore: keys,
            trialStore: InMemoryTrialStore(start: Date().addingTimeInterval(-(8 * 24 * 60 * 60))),
            snapshotStore: snapshots
        )
        await service.restoreOnLaunch()

        #expect(try! keys.loadKey() == "test-key")
        if case let .licensed(plan, _) = service.status {
            #expect(plan == .monthly)
        } else {
            Issue.record("Expected licensed status after offline grace, got \(service.status)")
        }
        #expect(service.entitlement.isUnlimited)
    }

    @Test("transport error with expired snapshot downgrades without deleting the key")
    func transportExpiredSnapshot() async {
        let keys = InMemoryLicenseKeyStore()
        try! keys.save(key: "test-key", instanceID: "instance-1")
        let snapshots = InMemorySnapshotStore(snapshot: .expired(plan: .annual))
        let client = MockLicenseClient()
        await client.setValidateFailure(.transport("offline"))

        let service = LicenseService(
            client: client,
            licenseStore: keys,
            trialStore: InMemoryTrialStore(start: Date().addingTimeInterval(-(8 * 24 * 60 * 60))),
            snapshotStore: snapshots
        )
        await service.restoreOnLaunch()

        #expect(try! keys.loadKey() == "test-key")
        #expect(service.status == .expired(plan: .annual))
        #expect(!service.entitlement.isUnlimited)
    }

    @Test("failed deactivate keeps the local key")
    func deactivateFailureKeepsKey() async {
        let keys = InMemoryLicenseKeyStore()
        try! keys.save(key: "test-key", instanceID: "instance-1")
        let snapshots = InMemorySnapshotStore(
            snapshot: .licensed(plan: .monthly, expiresAt: nil, at: Date())
        )
        let client = MockLicenseClient()
        await client.setDeactivateFailure(.transport("offline"))
        await client.setValidateSuccess(
            LicenseValidation(
                isValid: true,
                status: "active",
                plan: .monthly,
                expiresAt: nil,
                activationLimit: 5,
                activationUsage: 1
            )
        )

        let service = LicenseService(
            client: client,
            licenseStore: keys,
            trialStore: InMemoryTrialStore(start: Date()),
            snapshotStore: snapshots
        )
        await service.restoreOnLaunch()
        await service.deactivateAndRemoveLicense()

        #expect(try! keys.loadKey() == "test-key")
        #expect(service.lastError != nil)
        if case .licensed = service.status {
            // still licensed
        } else {
            Issue.record("Expected licensed status after failed deactivate, got \(service.status)")
        }
    }

    @Test("successful deactivate clears the key")
    func deactivateSuccessClearsKey() async {
        let keys = InMemoryLicenseKeyStore()
        try! keys.save(key: "test-key", instanceID: "instance-1")
        let snapshots = InMemorySnapshotStore(
            snapshot: .licensed(plan: .monthly, expiresAt: nil, at: Date())
        )
        let client = MockLicenseClient()
        await client.setValidateSuccess(
            LicenseValidation(
                isValid: true,
                status: "active",
                plan: .monthly,
                expiresAt: nil,
                activationLimit: 5,
                activationUsage: 1
            )
        )

        let service = LicenseService(
            client: client,
            licenseStore: keys,
            trialStore: InMemoryTrialStore(start: Date().addingTimeInterval(-(8 * 24 * 60 * 60))),
            snapshotStore: snapshots
        )
        await service.restoreOnLaunch()
        await service.deactivateAndRemoveLicense()

        #expect(try! keys.loadKey() == nil)
        #expect(service.status == .free)
        #expect(!service.entitlement.isUnlimited)
    }
}

extension MockLicenseClient {
    func setValidateFailure(_ error: LicenseError) {
        validateResult = .failure(error)
    }

    func setValidateSuccess(_ value: LicenseValidation) {
        validateResult = .success(value)
    }

    func setDeactivateFailure(_ error: LicenseError) {
        deactivateResult = .failure(error)
    }
}
