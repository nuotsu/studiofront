import Foundation

public enum SanityError: Error, LocalizedError, Sendable, Equatable {
    case unauthorized
    /// Authenticated but not allowed to access this resource (HTTP 403).
    /// Distinct from `.unauthorized` — the token is still valid.
    case forbidden
    case notFound
    case decoding
    case cancelled
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Session expired. Reconnect to continue."
        case .forbidden:
            "Sanity denied access to that resource."
        case .notFound:
            "Sanity couldn’t find that resource."
        case .decoding:
            "Sanity returned data in an unexpected shape."
        case .cancelled:
            nil
        case .transport(let message):
            SecretRedactor.redact(message)
        }
    }
}
