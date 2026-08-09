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

                    HStack {
                        Text("Theme")
                        Spacer()
                        ThemePicker(selection: $settings.themePreference)
                    }
                    .settingsHighlight(.theme)

                    HStack {
                        Text("Appearance")
                        Spacer()
                        AppearancePicker(selection: $settings.appearancePreference)
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

/// Shared chrome for a single-select preview tile: a small preview on top,
/// a label below, selection shown via accent border/background (no radio glyph).
private struct SettingsOptionTile<Preview: View>: View {
    var label: String
    var labelWidth: CGFloat
    var isSelected: Bool
    var action: () -> Void
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview()
                Text(label)
                    .foregroundStyle(.primary)
                    .frame(width: labelWidth)
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

// MARK: - Menu bar icon

private struct MenuBarIconPicker: View {
    @Binding var selection: MenuBarIconPreference

    var body: some View {
        HStack(spacing: 8) {
            ForEach(MenuBarIconPreference.allCases) { preference in
                SettingsOptionTile(
                    label: preference.title,
                    labelWidth: 72,
                    isSelected: selection == preference,
                    action: { selection = preference }
                ) {
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
                }
            }
        }
    }
}

// MARK: - Theme

private struct ThemePicker: View {
    @Binding var selection: ThemePreference

    var body: some View {
        HStack(spacing: 8) {
            ForEach(ThemePreference.allCases) { preference in
                SettingsOptionTile(
                    label: preference.title,
                    labelWidth: 84,
                    isSelected: selection == preference,
                    action: { selection = preference }
                ) {
                    ThemeSwatch(preference: preference)
                }
            }
        }
    }
}

private struct ThemeSwatch: View {
    var preference: ThemePreference

    var body: some View {
        let theme = preference.theme

        ZStack {
            if theme.surface.kind == .glass {
                GlassSurface(cornerRadius: 6)
            } else {
                RoundedRectangle(cornerRadius: 6, style: theme.cornerStyle)
                    .fill(theme.colors.panelFill)
            }

            RoundedRectangle(cornerRadius: theme.cornerRadius(5), style: theme.cornerStyle)
                .fill(theme.colors.primaryBackground)
                .frame(width: 18, height: 10)

            RoundedRectangle(cornerRadius: 6, style: theme.cornerStyle)
                .strokeBorder(theme.colors.panelBorder, lineWidth: 1)
        }
        .frame(width: 40, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: theme.cornerStyle))
    }
}

// MARK: - Appearance

private struct AppearancePicker: View {
    @Binding var selection: AppearancePreference

    var body: some View {
        HStack(spacing: 8) {
            ForEach(AppearancePreference.allCases) { preference in
                SettingsOptionTile(
                    label: preference.title,
                    labelWidth: 56,
                    isSelected: selection == preference,
                    action: { selection = preference }
                ) {
                    AppearanceSwatch(preference: preference)
                }
            }
        }
    }
}

/// Small window mockup (title strip + body) independent of the app's own
/// theme, mirroring how macOS represents its own Appearance setting.
private struct AppearanceSwatch: View {
    var preference: AppearancePreference

    private static let lightTop = Color(white: 0.82)
    private static let lightBody = Color.white
    private static let darkTop = Color(white: 0.32)
    private static let darkBody = Color(white: 0.16)

    var body: some View {
        HStack(spacing: 0) {
            switch preference {
            case .system:
                window(top: Self.lightTop, body: Self.lightBody)
                window(top: Self.darkTop, body: Self.darkBody)
            case .light:
                window(top: Self.lightTop, body: Self.lightBody)
            case .dark:
                window(top: Self.darkTop, body: Self.darkBody)
            }
        }
        .frame(width: 40, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func window(top: Color, body: Color) -> some View {
        VStack(spacing: 0) {
            top.frame(height: 6)
            body
        }
        .frame(maxWidth: .infinity)
    }
}
