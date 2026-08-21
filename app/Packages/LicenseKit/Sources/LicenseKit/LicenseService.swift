import Foundation
import Observation

@MainActor
@Observable
public final class LicenseService {
    public var status: LicenseStatus = .validating
    public var lastError: String?
    public private(set) var entitlement: Entitlement = .unlimited
    public var onEntitlementChange: ((Entitlement) -> Void)?

    private let licenseStore: LicenseKeyStore
    private let trialStore: TrialStore
    private let client: LicenseClient

    private var refreshGeneration = 0
    private var inFlight: Task<Void, Never>?
    private var lastCheckedAt: Date?

    private static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    public init(
        client: LicenseClient = .shared,
        licenseStore: LicenseKeyStore = .shared,
        trialStore: TrialStore = .shared
    ) {
        self.client = client
        self.licenseStore = licenseStore
        self.trialStore = trialStore
    }

    public func restoreOnLaunch() async {
        try? trialStore.recordStartIfNeeded()
        refresh()
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
            setStatus(licenseStatus(for: activation.status, plan: activation.plan, expiresAt: activation.expiresAt))
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
        if let key = try? licenseStore.loadKey(), let instanceID = try? licenseStore.loadInstanceID() {
            try? await client.deactivate(licenseKey: key, instanceID: instanceID)
        }
        try? licenseStore.delete()
        computeTrialOrFreeStatus()
    }

    public func refreshIfStale(interval: TimeInterval = 60 * 60 * 24) {
        let stale = lastCheckedAt.map { Date().timeIntervalSince($0) >= interval } ?? true
        guard stale else { return }
        refresh()
    }

    public func cancel() {
        refreshGeneration += 1
        inFlight?.cancel()
        inFlight = nil
    }

    private func refresh() {
        inFlight?.cancel()
        refreshGeneration += 1
        let generation = refreshGeneration
        status = .validating
        inFlight = Task {
            await self.performRevalidate(generation: generation)
            guard generation == self.refreshGeneration else { return }
            self.inFlight = nil
        }
    }

    private func performRevalidate(generation: Int) async {
        guard let key = try? licenseStore.loadKey(), !key.isEmpty else {
            guard generation == refreshGeneration else { return }
            computeTrialOrFreeStatus()
            return
        }
        let instanceID = try? licenseStore.loadInstanceID()
        do {
            let validation = try await client.validate(licenseKey: key, instanceID: instanceID)
            guard generation == refreshGeneration else { return }
            setStatus(licenseStatus(for: validation.status, plan: validation.plan ?? .unknown, expiresAt: validation.expiresAt))
            lastCheckedAt = Date()
            lastError = nil
        } catch let error as LicenseError {
            guard generation == refreshGeneration else { return }
            lastError = error.localizedDescription
            switch error {
            case .expired:
                setStatus(.expired(plan: .unknown))
            case .invalidKey, .notActivated:
                // The stored key is genuinely no good anymore (deleted/disabled
                // remotely) — drop it rather than keep retrying with it.
                try? licenseStore.delete()
                computeTrialOrFreeStatus()
            case .activationLimitReached, .transport, .decoding:
                // Don't punish an offline user or a transient API hiccup —
                // keep serving the last-known status/entitlement.
                break
            }
        } catch {
            guard generation == refreshGeneration else { return }
            lastError = "Couldn’t reach Lemon Squeezy."
        }
    }

    private func computeTrialOrFreeStatus() {
        guard let start = try? trialStore.loadStartDate() else {
            setStatus(.free)
            return
        }
        let remaining = Self.trialDuration - Date().timeIntervalSince(start)
        if remaining > 0 {
            let daysLeft = Int(ceil(remaining / (24 * 60 * 60)))
            setStatus(.trial(daysLeft: daysLeft))
        } else {
            setStatus(.free)
        }
    }

    private func licenseStatus(for status: String, plan: LicensePlan, expiresAt: Date?) -> LicenseStatus {
        status == "expired" ? .expired(plan: plan) : .licensed(plan: plan, expiresAt: expiresAt)
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
