import SwiftUI
import ThemeKit

struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPaneChrome(title: SettingsPane.appearance.title) {
            Form {
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
    }
}
