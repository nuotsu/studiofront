import Foundation

/// Single network entry point for Lemon Squeezy's License API. Typed errors
/// only. No API key: activate/validate/deactivate are designed to be called
/// with just the license key, straight from a customer's app.
public actor LicenseClient {
    public static let shared = LicenseClient()

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func activate(licenseKey: String, instanceName: String) async throws -> LicenseActivation {
        let dto: ActivateResponseDTO = try await post(
            path: "v1/licenses/activate",
            form: ["license_key": licenseKey, "instance_name": instanceName]
        )
        guard dto.activated, let instance = dto.instance, let key = dto.licenseKey else {
            throw mapError(status: dto.licenseKey?.status, message: dto.error)
        }
        return LicenseActivation(
            instanceID: instance.id,
            plan: LicensePlan.from(variantID: dto.meta?.variantId, variantName: dto.meta?.variantName),
            status: key.status,
            expiresAt: key.expiresAt,
            activationLimit: key.activationLimit,
            activationUsage: key.activationUsage
        )
    }

    public func validate(licenseKey: String, instanceID: String?) async throws -> LicenseValidation {
        var form = ["license_key": licenseKey]
        if let instanceID {
            form["instance_id"] = instanceID
        }
        let dto: ValidateResponseDTO = try await post(path: "v1/licenses/validate", form: form)
        guard dto.valid, let key = dto.licenseKey else {
            throw mapError(status: dto.licenseKey?.status, message: dto.error)
        }
        return LicenseValidation(
            isValid: dto.valid,
            status: key.status,
            plan: LicensePlan.from(variantID: dto.meta?.variantId, variantName: dto.meta?.variantName),
            expiresAt: key.expiresAt,
            activationLimit: key.activationLimit,
            activationUsage: key.activationUsage
        )
    }

    public func deactivate(licenseKey: String, instanceID: String) async throws {
        let dto: DeactivateResponseDTO = try await post(
            path: "v1/licenses/deactivate",
            form: ["license_key": licenseKey, "instance_id": instanceID]
        )
        guard dto.deactivated else {
            throw mapError(status: dto.licenseKey?.status, message: dto.error)
        }
    }

    private func mapError(status: String?, message: String?) -> LicenseError {
        switch status {
        case "expired": return .expired
        case "disabled": return .invalidKey
        default: break
        }
        if let message, message.localizedCaseInsensitiveContains("activation limit") {
            return .activationLimitReached
        }
        return .invalidKey
    }

    // MARK: - HTTP

    private func post<T: Decodable & Sendable>(path: String, form: [String: String]) async throws -> T {
        try Task.checkCancellation()
        var request = URLRequest(url: LemonSqueezyAPI.baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Self.encodeForm(form)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch is CancellationError {
            throw LicenseError.transport("Cancelled.")
        } catch let urlError as URLError where urlError.code == .cancelled {
            throw LicenseError.transport("Cancelled.")
        } catch {
            throw LicenseError.transport("Couldn’t reach Lemon Squeezy.")
        }

        guard let http = response as? HTTPURLResponse else {
            throw LicenseError.transport("Couldn’t reach Lemon Squeezy.")
        }

        // Lemon Squeezy returns the same JSON shape on both success (200) and
        // documented failure (4xx, e.g. an invalid or expired key) — decode
        // either way and let the caller inspect the boolean/`error` fields.
        switch http.statusCode {
        case 200..<500:
            do {
                return try LemonSqueezyJSON.decoder.decode(T.self, from: data)
            } catch {
                throw LicenseError.decoding
            }
        default:
            throw LicenseError.transport("Lemon Squeezy returned an unexpected response.")
        }
    }

    private static func encodeForm(_ params: [String: String]) -> Data {
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "+&="))
        let pairs = params.map { key, value -> String in
            let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
            let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(encodedKey)=\(encodedValue)"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}
