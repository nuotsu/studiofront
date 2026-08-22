import Foundation
import Observation

@MainActor
@Observable
public final class LicenseService {
    public var status: LicenseStatus = .validating
    public var lastError: String?
    public private(set) var entitlement: Entitlement = .free
    public var onEntitlementChange: ((Entitlement) -> Void)?

    private let licenseStore: any LicenseKeyStoring
    private let trialStore: any TrialStoring
    private let snapshotStore: any LicenseSnapshotStoring
    private let client: any LicenseNetworking

    private var refreshGeneration = 0
    private var inFlight: Task<Void, Never>?
    private var lastCheckedAt: Date?

    private static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    public init(
        client: any LicenseNetworking = LicenseClient.shared,
        licenseStore: any LicenseKeyStoring = LicenseKeyStore.shared,
        trialStore: any TrialStoring = TrialStore.shared,
        snapshotStore: any LicenseSnapshotStoring = LicenseSnapshotStore.shared
    ) {
        self.client = client
        self.licenseStore = licenseStore
        self.trialStore = trialStore
        self.snapshotStore = snapshotStore
    }

    public func restoreOnLaunch() async {
        try? trialStore.recordStartIfNeeded(now: Date())
        refresh(showValidating: true)
        await inFlight?.value
    }

    public func activate(licenseKey: String) async {
        lastError = nil
        let trimmed = licenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            lastError = "Paste a license key first."
            return
        }
        cancel()
        do {
            let activation = try await client.activate(licenseKey: trimmed, instanceName: Self.instanceName)
            try licenseStore.save(key: trimmed, instanceID: activation.instanceID)
            let newStatus = licenseStatus(for: activation.status, plan: activation.plan, expiresAt: activation.expiresAt)
            persistSnapshot(for: newStatus)
            setStatus(newStatus)
            lastCheckedAt = Date()
        } catch let error as LicenseError {
            lastError = error.localizedDescription
        } catch {
            lastError = "Couldn’t reach Lemon Squeezy."
        }
    }

    public func deactivateAndRemoveLicense() async {
        lastError = nil
        cancel()
        guard let key = try? licenseStore.loadKey(), let instanceID = try? licenseStore.loadInstanceID() else {
            try? licenseStore.delete()
            try? snapshotStore.delete()
            computeTrialOrFreeStatus()
            return
        }
        do {
            try await client.deactivate(licenseKey: key, instanceID: instanceID)
            try? licenseStore.delete()
            try? snapshotStore.delete()
            computeTrialOrFreeStatus()
        } catch let error as LicenseError {
            lastError = error.localizedDescription
        } catch {
            lastError = "Couldn’t reach Lemon Squeezy."
        }
    }

    public func refreshIfStale(interval: TimeInterval = 60 * 60 * 24) {
        let stale = lastCheckedAt.map { Date().timeIntervalSince($0) >= interval } ?? true
        guard stale else { return }
        // Keep the current concrete status visible while re-checking — never flash
        // `.validating` on every popover open.
        refresh(showValidating: false)
    }

    public func cancel() {
        refreshGeneration += 1
        inFlight?.cancel()
        inFlight = nil
    }

    private func refresh(showValidating: Bool) {
        inFlight?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        if showValidating {
            status = .validating
        }
        inFlight = Task {
            await self.performRevalidate(generation: generation)
            guard generation == self.refreshGeneration else { return }
            self.inFlight = nil
        }
    }

    private func performRevalidate(generation: Int) async {
        guard let key = try? licenseStore.loadKey(), !key.isEmpty else {
            guard generation == refreshGeneration else { return }
            try? snapshotStore.delete()
            computeTrialOrFreeStatus()
            return
        }
        let instanceID = try? licenseStore.loadInstanceID()
        do {
            let validation = try await client.validate(licenseKey: key, instanceID: instanceID)
            guard generation == refreshGeneration else { return }
            let newStatus = licenseStatus(for: validation.status, plan: validation.plan ?? .unknown, expiresAt: validation.expiresAt)
            persistSnapshot(for: newStatus)
            setStatus(newStatus)
            lastCheckedAt = Date()
            lastError = nil
        } catch let error as LicenseError {
            guard generation == refreshGeneration else { return }
            lastError = error.localizedDescription
            switch error {
            case .expired:
                let plan = (try? snapshotStore.load())?.plan ?? .unknown
                let snapshot = LicenseValidationSnapshot.expired(plan: plan)
                try? snapshotStore.save(snapshot)
                setStatus(.expired(plan: plan))
                lastCheckedAt = Date()
            case .invalidKey:
                // Remotely disabled / clearly invalid — drop local credentials.
                try? licenseStore.delete()
                try? snapshotStore.delete()
                computeTrialOrFreeStatus()
            case .notActivated:
                // Keep the key so the user can re-activate; apply trial/free caps.
                computeTrialOrFreeStatus()
            case .activationLimitReached, .transport, .decoding:
                applyOfflinePolicy()
            }
        } catch {
            guard generation == refreshGeneration else { return }
            lastError = "Couldn’t reach Lemon Squeezy."
            applyOfflinePolicy()
        }
    }

    private func applyOfflinePolicy() {
        if let snapshot = try? snapshotStore.load() {
            setStatus(LicenseOfflinePolicy.resolve(snapshot: snapshot))
        } else {
            // Never validated successfully on this install — do not unlock everything.
            computeTrialOrFreeStatus()
        }
        lastCheckedAt = Date()
    }

    private func computeTrialOrFreeStatus() {
        guard let start = try? trialStore.loadStartDate() else {
            setStatus(.free)
            lastCheckedAt = Date()
            return
        }
        let remaining = Self.trialDuration - Date().timeIntervalSince(start)
        if remaining > 0 {
            let daysLeft = Int(ceil(remaining / (24 * 60 * 60)))
            setStatus(.trial(daysLeft: daysLeft))
        } else {
            setStatus(.free)
        }
        lastCheckedAt = Date()
    }

    private func licenseStatus(for status: String, plan: LicensePlan, expiresAt: Date?) -> LicenseStatus {
        status == "expired" ? .expired(plan: plan) : .licensed(plan: plan, expiresAt: expiresAt)
    }

    private func persistSnapshot(for status: LicenseStatus) {
        switch status {
        case let .licensed(plan, expiresAt):
            try? snapshotStore.save(.licensed(plan: plan, expiresAt: expiresAt))
        case let .expired(plan):
            try? snapshotStore.save(.expired(plan: plan))
        default:
            break
        }
    }

    private func setStatus(_ newStatus: LicenseStatus) {
        status = newStatus
        if let resolved = newStatus.entitlement {
            entitlement = resolved
            onEntitlementChange?(resolved)
        }
    }

    private static var instanceName: String {
        ProcessInfo.processInfo.hostName
    }
}
