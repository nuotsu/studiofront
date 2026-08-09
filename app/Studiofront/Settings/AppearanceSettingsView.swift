import SwiftUI
import ThemeKit

struct AppearanceSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPaneChrome(title: SettingsPane.appearance.title) {
            Form {
                Section {
                    HStack {
                        Text("Menu bar icon")
                        Spacer()
                        MenuBarIconPicker(selection: $settings.menuBarIconPreference)
                    }
                    .settingsHighlight(.menuBarIcon)

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
        .onChange(of: settings.menuBarIconPreference) { _, preference in
            AppDelegate.shared?.applyMenuBarIcon(preference)
        }
    }
}

private struct MenuBarIconPicker: View {
    @Binding var selection: MenuBarIconPreference

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MenuBarIconPreference.allCases) { preference in
                MenuBarIconOption(preference: preference, isSelected: selection == preference) {
                    selection = preference
                }
            }
        }
    }
}

private struct MenuBarIconOption: View {
    var preference: MenuBarIconPreference
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(.regularMaterial)
                    Image(preference.imageName)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(height: 18)
                        .foregroundStyle(.primary)
                }
                .frame(width: 40, height: 24)

                Text(preference.title)
                    .foregroundStyle(.primary)
                    .frame(width: 72)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
