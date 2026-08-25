import Foundation

/// Last successful Lemon validation — used to enforce expiry and offline grace
/// when the network is unreachable.
public struct LicenseValidationSnapshot: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case licensed
        case expired
    }

    public var kind: Kind
    public var plan: LicensePlan
    public var expiresAt: Date?
    public var lastValidatedAt: Date

    public init(kind: Kind, plan: LicensePlan, expiresAt: Date?, lastValidatedAt: Date) {
        self.kind = kind
        self.plan = plan
        self.expiresAt = expiresAt
        self.lastValidatedAt = lastValidatedAt
    }

    public static func licensed(plan: LicensePlan, expiresAt: Date?, at date: Date = Date()) -> Self {
        .init(kind: .licensed, plan: plan, expiresAt: expiresAt, lastValidatedAt: date)
    }

    public static func expired(plan: LicensePlan, at date: Date = Date()) -> Self {
        .init(kind: .expired, plan: plan, expiresAt: nil, lastValidatedAt: date)
    }
}

/// Pure offline resolution — kept free of Keychain/network so it is unit-testable.
public enum LicenseOfflinePolicy: Sendable {
    /// How long a previously validated license stays unlimited without a successful Lemon check.
    public static let graceInterval: TimeInterval = 72 * 60 * 60

    public static func resolve(snapshot: LicenseValidationSnapshot, now: Date = Date()) -> LicenseStatus {
        switch snapshot.kind {
        case .expired:
            return .expired(plan: snapshot.plan)
        case .licensed:
            if let expiresAt = snapshot.expiresAt, expiresAt < now {
                return .expired(plan: snapshot.plan)
            }
            if now.timeIntervalSince(snapshot.lastValidatedAt) >= graceInterval {
                // Key stays on disk; next online validate can restore unlimited.
                return .free
            }
            return .licensed(plan: snapshot.plan, expiresAt: snapshot.expiresAt)
        }
    }
}
