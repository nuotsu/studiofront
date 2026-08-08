import Foundation

public enum SanityError: Error, LocalizedError, Sendable, Equatable {
    case unauthorized
    case notFound
    case decoding
    case cancelled
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            "Session expired. Reconnect to continue."
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
