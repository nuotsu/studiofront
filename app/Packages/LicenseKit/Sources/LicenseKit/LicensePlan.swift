import Foundation

public enum LicensePlan: String, Sendable, Codable {
    case monthly
    case annual
    case unknown

    private static let monthlyVariantID = 2_044_728
    private static let annualVariantID = 2_044_717

    static func from(variantID: Int?, variantName: String?) -> LicensePlan {
        if let variantID {
            if variantID == monthlyVariantID { return .monthly }
            if variantID == annualVariantID { return .annual }
        }
        if let variantName {
            let normalized = variantName.lowercased()
            if normalized.contains("month") { return .monthly }
            if normalized.contains("annual") || normalized.contains("year") { return .annual }
        }
        return .unknown
    }
}
