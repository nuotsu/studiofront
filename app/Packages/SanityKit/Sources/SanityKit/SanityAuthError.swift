import Foundation

public enum SanityAuthError: Error, LocalizedError, Sendable, Equatable {
    case notAuthenticated
    case unauthorized
    case invalidToken
    case cliConfigNotFound
    case cliTokenMissing
    case unreadable(String)
    case transport(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Not connected to Sanity."
        case .unauthorized:
            "Session expired. Reconnect to continue."
        case .invalidToken:
            "That token isn’t valid."
        case .cliConfigNotFound:
            "Sanity CLI config wasn’t found."
        case .cliTokenMissing:
            "The CLI config has no auth token."
        case .unreadable(let message), .transport(let message):
            SecretRedactor.redact(message)
        }
    }
}
