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

// MARK: - Menu bar icon

private struct MenuBarIconPicker: View {
    @Binding var selection: MenuBarIconPreference

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(MenuBarIconPreference.allCases) { preference in
                SettingsOptionTile(
                    label: preference.title,
                    labelWidth: SettingsOptionTileMetrics.labelWidth,
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
                    .frame(
                        width: SettingsOptionTileMetrics.previewWidth,
                        height: SettingsOptionTileMetrics.previewHeight
                    )
                }
            }
        }
    }
}

// MARK: - Preview tile (selection ring on the preview, not the label)

private enum SettingsOptionTileMetrics {
    /// Wide enough for "Studiofront" on one line; shared by menu bar + theme.
    static let previewWidth: CGFloat = 72
    static let previewHeight: CGFloat = 44
    static let labelWidth: CGFloat = 72

    /// Appearance tiles are 25% narrower/shorter than the shared preview size.
    static let appearancePreviewWidth: CGFloat = 54
    static let appearancePreviewHeight: CGFloat = 33
    static let appearanceLabelWidth: CGFloat = 54
}

/// Shared chrome for a single-select preview tile: a small preview on top,
/// a label below. Selection shows as an accent ring around the preview;
/// the label signals selection via text color/weight instead of a border.
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
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: isSelected ? 1.5 : 1
                            )
                    )
                    .frame(width: labelWidth, alignment: .center)
                Text(label)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .multilineTextAlignment(.center)
                    .frame(width: labelWidth, alignment: .center)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme

private struct ThemePicker: View {
    @Binding var selection: ThemePreference

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(ThemePreference.allCases) { preference in
                SettingsOptionTile(
                    label: preference.title,
                    labelWidth: SettingsOptionTileMetrics.labelWidth,
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

            RoundedRectangle(cornerRadius: preference == .sanityUI ? 2 : theme.cornerRadius(5), style: theme.cornerStyle)
                .fill(theme.colors.primaryBackground)
                .frame(width: 18, height: 10)

            RoundedRectangle(cornerRadius: 6, style: theme.cornerStyle)
                .strokeBorder(theme.colors.panelBorder, lineWidth: 1)
        }
        .frame(
            width: SettingsOptionTileMetrics.previewWidth,
            height: SettingsOptionTileMetrics.previewHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: theme.cornerStyle))
    }
}

// MARK: - Appearance

private struct AppearancePicker: View {
    @Binding var selection: AppearancePreference

    var body: some View {
        HStack(alignment: .top, spacing: 2) {
            ForEach(AppearancePreference.allCases) { preference in
                SettingsOptionTile(
                    label: preference.title,
                    labelWidth: SettingsOptionTileMetrics.appearanceLabelWidth,
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

    /// Inset window size — leaves a wallpaper margin inside the selection ring.
    private static let windowWidth: CGFloat = 40
    private static let windowHeight: CGFloat = 20

    var body: some View {
        ZStack {
            // Native-looking blue → purple desktop behind the window chrome.
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.30, green: 0.52, blue: 0.92),
                            Color(red: 0.42, green: 0.34, blue: 0.82),
                            Color(red: 0.22, green: 0.18, blue: 0.48),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

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
            .frame(width: Self.windowWidth, height: Self.windowHeight)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5)
            )
        }
        .frame(
            width: SettingsOptionTileMetrics.appearancePreviewWidth,
            height: SettingsOptionTileMetrics.appearancePreviewHeight
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func window(top: Color, body: Color) -> some View {
        VStack(spacing: 0) {
            top.frame(height: 5)
            body
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
