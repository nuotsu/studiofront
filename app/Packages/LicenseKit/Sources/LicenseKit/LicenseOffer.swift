import Foundation

/// Paid plan pricing and checkout links shown in Settings → License.
public enum LicenseOffer: String, CaseIterable, Sendable, Identifiable {
    case monthly
    case annual

    public var id: Self { self }

    public var plan: LicensePlan {
        switch self {
        case .monthly: .monthly
        case .annual: .annual
        }
    }

    public var title: String {
        switch self {
        case .monthly: "Monthly"
        case .annual: "Annual"
        }
    }

    /// Display price without the period suffix (e.g. `$10`).
    public var priceLabel: String {
        switch self {
        case .monthly: "$10"
        case .annual: "$84"
        }
    }

    public var periodLabel: String {
        switch self {
        case .monthly: "mo"
        case .annual: "yr"
        }
    }

    public var caption: String {
        switch self {
        case .monthly: "Billed monthly"
        case .annual: "Billed annually"
        }
    }

    public var savingsBadge: String? {
        switch self {
        case .monthly: nil
        case .annual: "Save \(Self.annualSavingsPercent)%!"
        }
    }

    public var isRecommended: Bool {
        self == .annual
    }

    public var checkoutURL: URL {
        switch self {
        case .monthly: LemonSqueezyAPI.monthlyCheckoutURL
        case .annual: LemonSqueezyAPI.annualCheckoutURL
        }
    }

    /// `(monthly × 12 − annual) / (monthly × 12)`, rounded to the nearest percent.
    public static let annualSavingsPercent: Int = {
        let monthlyYearly = 10 * 12
        let annual = 84
        return Int((Double(monthlyYearly - annual) / Double(monthlyYearly) * 100).rounded())
    }()
}
