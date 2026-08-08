import SwiftUI
import ThemeKit

struct GeneralSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPaneChrome(title: SettingsPane.general.title) {
            Form {
                Section {
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

                    Toggle("Hide archived projects", isOn: $settings.hideArchivedProjects)
                        .settingsHighlight(.hideArchivedProjects)
                }

                Section {
                    Picker("Theme", selection: $settings.themePreference) {
                        ForEach(ThemePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .settingsHighlight(.theme)

                    Picker("Appearance", selection: $settings.appearancePreference) {
                        ForEach(AppearancePreference.allCases) { preference in
                            Text(preference.title).tag(preference)
                        }
                    }
                    .settingsHighlight(.appearance)
                }
            }
            .formStyle(.grouped)
        }
        .onChange(of: settings.appearancePreference) { _, preference in
            AppDelegate.shared?.applyAppearance(preference)
        }
        .onChange(of: settings.showInDock) { _, _ in
            AppDelegate.shared?.applyActivationPolicy()
        }
    }
}
