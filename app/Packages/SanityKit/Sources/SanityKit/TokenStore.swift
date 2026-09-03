import Foundation
import Security

/// Keychain-only token storage. Never UserDefaults, SwiftData, or a plist.
public struct TokenStore: Sendable {
    public static let shared = TokenStore()

    private let service = "dev.nuotsu.Studiofront.sanity"
    private let account = "authToken"
    private let sourceDefaultsKey = "sanity.tokenSource"

    public init() {}

    public func load() throws -> String? {
        switch KeychainPassword.readData(service: service, account: account) {
        case .missing:
            return nil
        case .value(let data):
            return String(data: data, encoding: .utf8)
        case .inaccessible:
            throw SanityAuthError.unreadable("Couldn’t read the saved token.")
        }
    }

    public func source() -> TokenSource? {
        TokenSource(rawValue: UserDefaults.standard.string(forKey: sourceDefaultsKey) ?? "")
    }

    public func save(token: String, source: TokenSource) throws {
        try delete()
        let status = KeychainPassword.addData(Data(token.utf8), service: service, account: account)
        guard status == errSecSuccess else {
            throw SanityAuthError.unreadable("Couldn’t save the token securely.")
        }
        UserDefaults.standard.set(source.rawValue, forKey: sourceDefaultsKey)
    }

    public func delete() throws {
        let status = KeychainPassword.delete(service: service, account: account)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SanityAuthError.unreadable("Couldn’t clear the saved token.")
        }
        UserDefaults.standard.removeObject(forKey: sourceDefaultsKey)
    }
}
