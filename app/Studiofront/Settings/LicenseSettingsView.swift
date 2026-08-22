import SwiftUI
import LicenseKit

struct LicenseSettingsView: View {
    @Environment(LicenseService.self) private var license
    @State private var keyDraft = ""
    @State private var isActivating = false
    @State private var confirmDeactivate = false

    var body: some View {
        SettingsPaneChrome(title: SettingsPane.license.title) {
            Form {
                switch license.status {
                case let .licensed(plan, expiresAt):
                    licensedSection(plan: plan, expiresAt: expiresAt)
                case .validating, .trial, .free, .expired:
                    statusSection
                    upgradeSection
                    activateSection
                }
            }
            .formStyle(.grouped)
        }
        .alert("Deactivate This Device?", isPresented: $confirmDeactivate) {
            Button("Cancel", role: .cancel) {}
            Button("Deactivate", role: .destructive) {
                Task { await license.deactivateAndRemoveLicense() }
            }
        } message: {
            Text("This device will go back to the free plan (3 projects across 3 organizations).")
        }
    }

    // MARK: - Status

    @ViewBuilder
    private var statusSection: some View {
        Section {
            switch license.status {
            case .validating:
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking license…")
                        .foregroundStyle(.secondary)
                }
            case let .trial(daysLeft):
                statusHeader(
                    title: "Trial",
                    caption: daysLeft == 1
                        ? "1 day left. Unlimited access until then."
                        : "\(daysLeft) days left. Unlimited access until then."
                )
            case .free:
                statusHeader(
                    title: "Free plan",
                    caption: "3 projects across 3 organizations."
                )
            case let .expired(plan):
                statusHeader(
                    title: "Subscription ended",
                    caption: "You’re back on the free plan — 3 projects across 3 organizations."
                )
                .accessibilityLabel("\(plan.title) subscription ended. You’re back on the free plan.")
            case .licensed:
                EmptyView()
            }
        }
    }

    private func statusHeader(title: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            Text(caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    // MARK: - Upgrade

    private var upgradeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Upgrade")
                        .font(.headline)
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("Unlimited projects and organizations. ")
                            .foregroundStyle(.secondary)
                        Link(
                            "See all plans",
                            destination: URL(string: "https://studiofront.nuots.dev/pricing")!
                        )
                        .buttonStyle(SettingsInlineLinkButtonStyle())
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    ForEach(LicenseOffer.allCases) { offer in
                        planCard(offer)
                    }
                }
                // Room for the Annual "Best Deal" badge sitting on the top border.
                .padding(.top, 10)

                Text("You’ll receive an email with a license key to paste below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
        }
    }

    private func planCard(_ offer: LicenseOffer) -> some View {
        let isExpired: Bool = {
            if case .expired = license.status { return true }
            return false
        }()
        let cta = isExpired ? "Renew" : "Subscribe"

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(offer.title)
                    .font(.headline)
                if let savingsBadge = offer.savingsBadge {
                    Text(savingsBadge)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .lineLimit(1)
                        .fixedSize()
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(offer.priceLabel)
                    .font(.title2.weight(.semibold).monospacedDigit())
                Text("/ \(offer.periodLabel)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text(offer.caption)
                .font(.caption)
                .foregroundStyle(.secondary)

            Group {
                if offer.isRecommended {
                    Link(cta, destination: offer.checkoutURL)
                        .buttonStyle(.borderedProminent)
                } else {
                    Link(cta, destination: offer.checkoutURL)
                        .buttonStyle(.bordered)
                }
            }
            .controlSize(.small)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    offer.isRecommended ? Color.accentColor : Color.primary.opacity(0.12),
                    lineWidth: offer.isRecommended ? 1.5 : 1
                )
        )
        .overlay(alignment: .topTrailing) {
            if offer.isRecommended {
                floatingBadge("Best Deal", fill: Color.accentColor)
                    .padding(.trailing, 10)
                    .offset(y: -10)
            }
        }
    }

    private func floatingBadge(_ title: String, fill: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(fill, in: Capsule())
    }

    // MARK: - Activate

    private var activateSection: some View {
        Section("Already have a license key?") {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("License key")
                    SecureField("", text: $keyDraft, prompt: Text("Paste your license key"))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.leading)
                        .labelsHidden()
                        .disabled(isActivating)
                }
                .settingsHighlight(.licenseKey)

                Button {
                    activate()
                } label: {
                    HStack(spacing: 6) {
                        if isActivating {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Activate")
                    }
                }
                .disabled(
                    isActivating
                        || keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )

                if let message = license.lastError {
                    Text(message)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Licensed

    private func licensedSection(plan: LicensePlan, expiresAt: Date?) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(plan.title)
                    .font(.headline)
                Text("Unlimited projects and organizations.")
                    .foregroundStyle(.secondary)
                if let expiresAt {
                    Text("Access through \(expiresAt.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
            .settingsHighlight(.licenseKey)

            Button("Deactivate This Device", role: .destructive) {
                confirmDeactivate = true
            }
        }
    }

    // MARK: - Actions

    private func activate() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !isActivating else { return }
        isActivating = true
        Task {
            await license.activate(licenseKey: key)
            isActivating = false
            if case .licensed = license.status {
                keyDraft = ""
            }
        }
    }
}

private struct SettingsInlineLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(Color.accentColor)
            .opacity(configuration.isPressed ? 0.45 : 1)
    }
}
