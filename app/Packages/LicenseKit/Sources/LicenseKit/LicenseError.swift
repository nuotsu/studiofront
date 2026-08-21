import Foundation

public enum LicenseError: Error, LocalizedError, Sendable, Equatable {
    case invalidKey
    case notActivated
    case activationLimitReached
    case expired
    case transport(String)
    case decoding

    public var errorDescription: String? {
        switch self {
        case .invalidKey:
            "That license key isn't valid."
        case .notActivated:
            "This license key hasn't been activated on this device."
        case .activationLimitReached:
            "This license key has reached its device limit. Deactivate another device first."
        case .expired:
            "This license has expired. Renew your subscription to restore full access."
        case .transport(let message):
            LicenseSecretRedactor.redact(message)
        case .decoding:
            "Lemon Squeezy returned data in an unexpected shape."
        }
    }
}
