import Foundation
import Observation
import SanityKit

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case account
    case keybindings

    var id: Self { self }

    var title: String {
        switch self {
        case .general: "General"
        case .account: "Account"
        case .keybindings: "Keybindings"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .account: "person.crop.circle"
        case .keybindings: "keyboard"
        }
    }
}

@MainActor
@Observable
final class AuthSession {
    enum Status: Equatable {
        case signedOut
        case connecting
        case signedIn(SanityUser, TokenSource)
        case reconnectRequired
    }

    var status: Status = .signedOut
    var selectedSettingsPane: SettingsPane = .general
    var cliProbe = CLICredentialReader.probe()
    var lastError: String?
    var onStatusChange: (() -> Void)?

    private let tokens = TokenStore.shared
    private let client = SanityClient.shared

    var isSignedIn: Bool {
        if case .signedIn = status { return true }
        return false
    }

    var needsReconnect: Bool {
        status == .reconnectRequired
    }

    var signedInUser: SanityUser? {
        if case let .signedIn(user, _) = status { return user }
        return nil
    }

    var tokenSource: TokenSource? {
        if case let .signedIn(_, source) = status { return source }
        return tokens.source()
    }

    func refreshCLIDetection() {
        cliProbe = CLICredentialReader.probe()
    }

    func restoreOnLaunch() async {
        refreshCLIDetection()
        guard let token = try? tokens.load(), !token.isEmpty else {
            status = .signedOut
            return
        }
        await validate(token: token, source: tokens.source() ?? .manual, persist: false)
    }

    func importCLIToken() async {
        lastError = nil
        do {
            let token = try CLICredentialReader.readAuthToken()
            await validate(token: token, source: .cli, persist: true)
        } catch let error as SanityAuthError {
            lastError = error.localizedDescription
        } catch {
            lastError = "Couldn’t read the Sanity CLI login."
        }
    }

    func importCLIConfig(from url: URL) async {
        lastError = nil
        do {
            _ = try CLICredentialReader.makeBookmark(for: url)
            let token = try CLICredentialReader.readAuthToken(from: url, scoped: true)
            await validate(token: token, source: .cli, persist: true)
            refreshCLIDetection()
        } catch let error as SanityAuthError {
            lastError = error.localizedDescription
        } catch {
            lastError = "Couldn’t read that config file."
        }
    }

    func saveManualToken(_ raw: String) async {
        lastError = nil
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            lastError = "Paste a personal token first."
            return
        }
        await validate(token: token, source: .manual, persist: true)
    }

    func signOut() {
        lastError = nil
        try? tokens.delete()
        status = .signedOut
        refreshCLIDetection()
        onStatusChange?()
    }

    func markReconnectRequired() {
        status = .reconnectRequired
        onStatusChange?()
    }

    private func validate(token: String, source: TokenSource, persist: Bool) async {
        status = .connecting
        do {
            let user = try await client.currentUser(token: token)
            if persist {
                try tokens.save(token: token, source: source)
            }
            status = .signedIn(user, source)
            lastError = nil
            onStatusChange?()
        } catch SanityAuthError.unauthorized, SanityAuthError.invalidToken {
            if persist {
                lastError = SanityAuthError.invalidToken.localizedDescription
                status = .signedOut
            } else {
                status = .reconnectRequired
            }
            onStatusChange?()
        } catch let error as SanityAuthError {
            lastError = error.localizedDescription
            status = persist ? .signedOut : .reconnectRequired
            onStatusChange?()
        } catch {
            lastError = "Couldn’t reach Sanity."
            status = persist ? .signedOut : .reconnectRequired
            onStatusChange?()
        }
    }
}
