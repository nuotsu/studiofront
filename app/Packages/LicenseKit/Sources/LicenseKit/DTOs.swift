import Foundation

enum LemonSqueezyJSON {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            if let date = try? Date(string, strategy: Date.ISO8601FormatStyle()) {
                return date
            }
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Invalid date")
            )
        }
        return decoder
    }()
}

struct LemonSqueezyMetaDTO: Decodable {
    var variantId: Int?
    var variantName: String?
}

struct LemonSqueezyLicenseKeyDTO: Decodable {
    var status: String
    var activationLimit: Int
    var activationUsage: Int
    var expiresAt: Date?
}

struct LemonSqueezyInstanceDTO: Decodable {
    var id: String
    var name: String
}

struct ActivateResponseDTO: Decodable {
    var activated: Bool
    var error: String?
    var licenseKey: LemonSqueezyLicenseKeyDTO?
    var instance: LemonSqueezyInstanceDTO?
    var meta: LemonSqueezyMetaDTO?
}

struct ValidateResponseDTO: Decodable {
    var valid: Bool
    var error: String?
    var licenseKey: LemonSqueezyLicenseKeyDTO?
    var instance: LemonSqueezyInstanceDTO?
    var meta: LemonSqueezyMetaDTO?
}

struct DeactivateResponseDTO: Decodable {
    var deactivated: Bool
    var error: String?
    var licenseKey: LemonSqueezyLicenseKeyDTO?
}

public struct LicenseActivation: Sendable {
    public let instanceID: String
    public let plan: LicensePlan
    public let status: String
    public let expiresAt: Date?
    public let activationLimit: Int
    public let activationUsage: Int
}

public struct LicenseValidation: Sendable {
    public let isValid: Bool
    public let status: String
    public let plan: LicensePlan?
    public let expiresAt: Date?
    public let activationLimit: Int
    public let activationUsage: Int
}
