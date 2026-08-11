import AppKit
import SwiftUI

struct AboutSettingsView: View {
    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        SettingsPaneChrome(title: SettingsPane.about.title) {
            VStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 96, height: 96)

                VStack(spacing: 4) {
                    Text("Studiofront")
                        .font(.title2.weight(.semibold))
                    Text("A native macOS menu bar app to manage Sanity Studios across organizations.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Text("Version \(version) (\(build))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Link("Repository", destination: URL(string: "https://github.com/nuotsu/studiofront")!)
                    Link("Homepage", destination: URL(string: "https://studiofront.nuotsu.dev")!)
                    Link("Docs", destination: URL(string: "https://studiofront.nuotsu.dev/docs")!)
                }
                .font(.callout)

                HStack(spacing: 4) {
                    Text("Developed by")
                        .foregroundStyle(.secondary)
                    Link("nuotsu", destination: URL(string: "https://nuotsu.dev")!)
                }
                .font(.footnote)

                Button("Check for Updates…") {
                    AppUpdater.shared.checkForUpdates(nil)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 40)
            .padding(.horizontal, 20)
            .settingsHighlight(.about)
        }
    }
}
