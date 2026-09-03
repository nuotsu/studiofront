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
        switch KeychainPassword.readData(service: service, account: account) {
        case .missing:
            return nil
        case .value(let data):
            guard let string = String(data: data, encoding: .utf8) else {
                throw LicenseError.transport("Couldn’t read the trial start date.")
            }
            return try? Date(string, strategy: Date.ISO8601FormatStyle())
        case .inaccessible:
            throw LicenseError.transport("Couldn’t read the trial start date.")
        }
    }

    /// No-ops if a start date already exists — first-launch-only write.
    public func recordStartIfNeeded(now: Date = Date()) throws {
        guard try loadStartDate() == nil else { return }
        let status = KeychainPassword.addData(Data(now.ISO8601Format().utf8), service: service, account: account)
        guard status == errSecSuccess else {
            throw LicenseError.transport("Couldn’t record the trial start date.")
        }
    }
}
