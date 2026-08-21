import SwiftUI
import LicenseKit

struct LicenseSettingsView: View {
    @Environment(LicenseService.self) private var license
    @State private var keyDraft = ""

    var body: some View {
        SettingsPaneChrome(title: SettingsPane.license.title, description: descriptionText) {
            Form {
                statusSection
                if !isLicensed {
                    activateSection
                    upgradeSection
                }
                if let message = license.lastError {
                    Section {
                        Text(message)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var isLicensed: Bool {
        if case .licensed = license.status { return true }
        return false
    }

    private var descriptionText: String? {
        switch license.status {
        case .validating, .licensed:
            nil
        case .trial:
            "Free trial — all projects and organizations unlocked."
        case .free:
            "Free plan — 3 projects across 3 organizations."
        case .expired:
            "Your subscription has lapsed."
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            switch license.status {
            case .validating:
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking license…")
                }
            case let .trial(daysLeft):
                Text(daysLeft == 1 ? "1 day left in your trial." : "\(daysLeft) days left in your trial.")
            case .free:
                Text("You're on the free plan.")
            case let .licensed(plan, expiresAt):
                VStack(alignment: .leading, spacing: 4) {
                    Text("Unlimited projects and organizations — \(plan.title)")
                        .font(.headline)
                    if let expiresAt {
                        Text("Renews \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Deactivate This Device", role: .destructive) {
                    Task { await license.deactivateAndRemoveLicense() }
                }
            case let .expired(plan):
                Text("Your \(plan.title) subscription has lapsed. Renew to unlock unlimited projects again.")
            }
        }
        .settingsHighlight(.licenseKey)
    }

    private var activateSection: some View {
        Section("Activate a license") {
            TextField(text: $keyDraft, prompt: Text("Paste your license key")) {
                Text("License key")
            }
            .textFieldStyle(.roundedBorder)
            Button("Activate") {
                let key = keyDraft
                keyDraft = ""
                Task { await license.activate(licenseKey: key) }
            }
            .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var upgradeSection: some View {
        Section("Upgrade") {
            Link("Upgrade — $10/mo or $84/yr", destination: LemonSqueezyAPI.checkoutURL)
        }
    }
}

private extension LicensePlan {
    var title: String {
        switch self {
        case .monthly: "Monthly"
        case .annual: "Annual"
        case .unknown: "Subscription"
        }
    }
}
