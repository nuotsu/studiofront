import SwiftUI
import ThemeKit

struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPaneChrome(title: SettingsPane.general.title) {
            Form {
                Section {
                    Toggle("Launch at Login", isOn: $settings.launchAtLogin)
                        .settingsHighlight(.launchAtLogin)
                    Toggle("Show in Dock", isOn: $settings.showInDock)
                        .settingsHighlight(.showInDock)
                }

                Section {
                    Picker("Refresh interval", selection: $settings.refreshIntervalMinutes) {
                        ForEach(AppSettings.allowedRefreshIntervals, id: \.self) { minutes in
                            Text(minutes == 1 ? "Every minute" : "Every \(minutes) minutes").tag(minutes)
                        }
                    }
                    .settingsHighlight(.refreshInterval)

                    Picker(selection: $settings.studioURLPreference) {
                        ForEach(StudioURLPreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Studio URL Preference")
                            Text("When a project has both a custom-domain Studio and a default *.sanity.studio URL, this decides which one the Studio button opens.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .settingsHighlight(.studioURLPreference)

                    Toggle("Hide archived projects", isOn: $settings.hideArchivedProjects)
                        .settingsHighlight(.hideArchivedProjects)
                }

                Section {
                    Picker("Editor Avatars", selection: $settings.presenceMode) {
                        ForEach(PresenceMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .settingsHighlight(.presenceMode)
                    Text(settings.presenceMode.caption)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: settings.showInDock) { _, _ in
            AppDelegate.shared?.applyActivationPolicy()
        }
    }
}
