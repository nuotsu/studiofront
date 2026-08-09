import AppKit
import SwiftUI
import SanityKit
import UniformTypeIdentifiers

struct AccountSettingsView: View {
    @Environment(AuthSession.self) private var auth
    @State private var tokenDraft = ""

    var body: some View {
        SettingsPaneChrome(
            title: SettingsPane.account.title,
            description: auth.isSignedIn ? nil : "Connect a Sanity account to load live projects."
        ) {
            Form {
                identitySection
                if !auth.isSignedIn {
                    cliSection
                    manualSection
                }
                if let message = auth.lastError {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
        .onAppear {
            auth.refreshCLIDetection()
        }
    }

    @ViewBuilder
    private var identitySection: some View {
        // Signed out, the pane header already says everything this section would,
        // so the whole group (and its duplicate "Account" heading) drops away.
        if auth.status != .signedOut {
            Section(auth.isSignedIn ? "Connected account" : "Account") {
                switch auth.status {
                case .connecting:
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Connecting…")
                    }
                    .settingsHighlight(.accountIdentity)
                case let .signedIn(user, source):
                    HStack(spacing: 12) {
                        avatar(for: user)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.name)
                                .font(.headline)
                            if let email = user.email, !email.isEmpty {
                                Text(email)
                                    .foregroundStyle(.secondary)
                            }
                            Text("Token source: \(source.title)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(.accountIdentity)
                    Button("Sign Out", role: .destructive) {
                        auth.signOut()
                        tokenDraft = ""
                    }
                    .settingsHighlight(.signOut)
                case .reconnectRequired:
                    Text("Session expired. Sign in again with your CLI login or a personal token.")
                        .settingsHighlight(.accountIdentity)
                    Button("Reconnect with Sanity CLI") {
                        Task { await auth.importCLIToken() }
                    }
                    .disabled(!auth.cliProbe.isReadable)
                    .settingsHighlight(.cliLogin)
                case .signedOut:
                    EmptyView()
                }
            }
        }
    }

    private var cliSection: some View {
        Section("Sanity CLI") {
            if auth.cliProbe.isReadable && auth.cliProbe.hasTokenKey {
                Text("Found a Sanity CLI login at \(auth.cliProbe.url.path).")
                    .foregroundStyle(.secondary)
                Button("Use your existing Sanity CLI login") {
                    Task { await auth.importCLIToken() }
                }
            } else if auth.cliProbe.isReadable {
                Text("Found \(auth.cliProbe.url.path), but it has no auth token. Run `sanity login` in a terminal, then try again.")
                    .foregroundStyle(.secondary)
            } else {
                Text("Can’t read ~/.config/sanity/config.json from the sandbox. Choose the file once to grant access, or paste a token below.")
                    .foregroundStyle(.secondary)
            }
            Button("Choose config.json…") {
                chooseCLIConfig()
            }
        }
        .settingsHighlight(.cliLogin)
    }

    private var manualSection: some View {
        Section("Personal token") {
            SecureField("Personal token", text: $tokenDraft)
            Button("Save token") {
                let token = tokenDraft
                tokenDraft = ""
                Task { await auth.saveManualToken(token) }
            }
            .disabled(tokenDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Link(
                "How to create a token",
                destination: URL(string: "https://www.sanity.io/docs/content-lake/http-auth")!
            )
        }
        .settingsHighlight(.personalToken)
    }

    private func avatar(for user: SanityUser) -> some View {
        Group {
            if let url = user.profileImageURL {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initials(user.name)
                }
            } else {
                initials(user.name)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private func initials(_ name: String) -> some View {
        let letters = name.split(whereSeparator: \.isWhitespace).prefix(2).compactMap(\.first).map(String.init).joined()
        return Text(letters.uppercased())
            .font(.headline)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.2))
    }

    private func chooseCLIConfig() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = CLICredentialReader.defaultConfigURL.deletingLastPathComponent()
        panel.message = "Select your Sanity CLI config.json"
        panel.prompt = "Use"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await auth.importCLIConfig(from: url) }
    }
}
