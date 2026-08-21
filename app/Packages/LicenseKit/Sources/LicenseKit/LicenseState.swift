import Foundation

public enum LicenseStatus: Equatable, Sendable {
    case validating
    case trial(daysLeft: Int)
    case free
    case licensed(plan: LicensePlan, expiresAt: Date?)
    case expired(plan: LicensePlan)
}

public struct Entitlement: Sendable, Equatable {
    public var isUnlimited: Bool
    public var maxFavoriteProjects: Int
    public var maxFavoriteOrganizations: Int

    public init(isUnlimited: Bool, maxFavoriteProjects: Int, maxFavoriteOrganizations: Int) {
        self.isUnlimited = isUnlimited
        self.maxFavoriteProjects = maxFavoriteProjects
        self.maxFavoriteOrganizations = maxFavoriteOrganizations
    }

    public static let unlimited = Entitlement(isUnlimited: true, maxFavoriteProjects: .max, maxFavoriteOrganizations: .max)
    public static let free = Entitlement(isUnlimited: false, maxFavoriteProjects: 3, maxFavoriteOrganizations: 3)
}

public extension LicenseStatus {
    /// `nil` for `.validating` — `LicenseService` only updates its stored
    /// entitlement when this resolves to a concrete value, so a background
    /// revalidation never flashes rows to locked while a stale-but-still-good
    /// license is being re-checked.
    var entitlement: Entitlement? {
        switch self {
        case .validating:
            nil
        case .trial, .licensed:
            .unlimited
        case .free, .expired:
            .free
        }
    }
}
