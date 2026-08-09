import SwiftUI
import ThemeKit

struct KeybindingsSettingsView: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        SettingsPaneChrome(
            title: SettingsPane.keybindings.title,
            description: "Click to configure custom binding"
        ) {
            Form {
                Section("Navigation") {
                    KeybindingRow(label: "Move selection up", glyphs: [.symbol("arrow.up")])
                        .settingsHighlight(.keybindingsOverview)
                    KeybindingRow(label: "Move selection down", glyphs: [.symbol("arrow.down")])
                    KeybindingRow(label: "Close popover / clear search", glyphs: [.symbol("escape")])
                }

                Section("Actions") {
                    ConfigurableKeybindingRow(
                        label: "Open Studio",
                        keyCode: $settings.openStudioKeyCode,
                        modifierRawValue: $settings.openStudioModifierRawValue,
                        characters: $settings.openStudioCharacters
                    )
                    .settingsHighlight(.openStudioShortcut)
                    KeybindingRow(label: "Copy project ID", glyphs: [.symbol("command"), .text("C")])
                    KeybindingRow(label: "Toggle favorite", glyphs: [.symbol("command"), .text("F")])
                    KeybindingRow(label: "Refresh", glyphs: [.symbol("command"), .text("R")])
                    KeybindingRow(label: "Jump to favorite", glyphs: [.symbol("command"), .text("1–9")])
                }

                Section("Search") {
                    KeybindingRow(label: "Focus search", glyphs: [.symbol("command"), .text("K")])
                }

                Section("Window") {
                    KeybindingRow(label: "Open Settings", glyphs: [.symbol("command"), .text(",")])
                }
            }
            .formStyle(.grouped)
        }
    }
}

private struct KeybindingRow: View {
    var label: String
    var glyphs: [KeyGlyph]

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            KeycapLegend(glyphs)
        }
        .foregroundStyle(.secondary)
        .opacity(0.55)
        .disabled(true)
    }
}

private struct ConfigurableKeybindingRow: View {
    var label: String
    @Binding var keyCode: Int
    @Binding var modifierRawValue: Int
    @Binding var characters: String

    @State private var isRecording = false

    private var isDefault: Bool {
        keyCode == AppSettings.defaultOpenStudioKeyCode
            && modifierRawValue == AppSettings.defaultOpenStudioModifierRawValue
    }

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Button("Reset") {
                isRecording = false
                keyCode = AppSettings.defaultOpenStudioKeyCode
                modifierRawValue = AppSettings.defaultOpenStudioModifierRawValue
                characters = ""
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(isDefault ? Color.secondary.opacity(0.5) : Color.blue)
            .disabled(isDefault)
            ShortcutRecorderControl(
                keyCode: $keyCode,
                modifierRawValue: $modifierRawValue,
                characters: $characters,
                isRecording: $isRecording
            )
        }
    }
}
