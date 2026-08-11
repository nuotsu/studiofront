import AppKit
import SwiftUI
import ThemeKit

enum KeyGlyphMapping {
    static func glyph(forKeyCode keyCode: UInt16, characters: String) -> KeyGlyph {
        switch AppSettings.normalizedOpenStudioKeyCode(keyCode) {
        case 36: return .symbol("return")
        case 53: return .symbol("escape")
        case 123: return .symbol("arrow.left")
        case 124: return .symbol("arrow.right")
        case 125: return .symbol("arrow.down")
        case 126: return .symbol("arrow.up")
        default:
            let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
            return .text(trimmed.isEmpty ? "Key \(keyCode)" : trimmed.uppercased())
        }
    }

    static func modifierGlyphs(_ flags: NSEvent.ModifierFlags) -> [KeyGlyph] {
        var glyphs: [KeyGlyph] = []
        if flags.contains(.control) { glyphs.append(.symbol("control")) }
        if flags.contains(.option) { glyphs.append(.symbol("option")) }
        if flags.contains(.shift) { glyphs.append(.symbol("shift")) }
        if flags.contains(.command) { glyphs.append(.symbol("command")) }
        return glyphs
    }
}

/// Shortcuts already used by fixed, non-configurable bindings — mirrors the fixed
/// cases hardcoded in `AppDelegate.handlePopoverKey`. Kept as a small local table
/// since that set is stable; update both places together if it ever changes.
private enum ReservedShortcut {
    static func description(command: Bool, keyCode: UInt16, characters: String) -> String? {
        if command {
            switch characters.lowercased() {
            case "c": return "Already used by ⌘C — Copy project ID"
            case "r": return "Already used by ⌘R — Refresh"
            case ",": return "Already used by ⌘, — Open Settings"
            case "k": return "Already used by ⌘K — Focus search"
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                return "Already used by ⌘\(characters) — Jump to favorite"
            default: return nil
            }
        }
        switch AppSettings.normalizedOpenStudioKeyCode(keyCode) {
        case 126: return "Already used by ↑ — Move selection up"
        case 125: return "Already used by ↓ — Move selection down"
        case 53: return "Already used by Esc — Close popover / clear search"
        default: return nil
        }
    }
}

/// Records a new keyboard shortcut into the given keyCode/modifier bindings.
/// While recording, a scoped local key monitor swallows every keydown until one is
/// captured (or Escape cancels without changing the binding). `isRecording` is owned
/// by the caller so external actions (e.g. a "Reset" button) can end an in-progress
/// recording — the monitor's lifecycle is driven entirely by changes to that binding.
struct ShortcutRecorderControl: View {
    @Environment(\.studioTheme) private var theme

    @Binding var keyCode: Int
    @Binding var modifierRawValue: Int
    @Binding var characters: String
    @Binding var isRecording: Bool

    @State private var monitor: Any?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                isRecording.toggle()
            } label: {
                Group {
                    if isRecording {
                        Text("Recording")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.red)
                    } else {
                        currentLegend
                    }
                }
                .frame(minHeight: 14)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(theme.colors.chipBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(isRecording ? Color.red.opacity(0.35) : theme.colors.chipBorder, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isRecording ? "Recording new shortcut" : "Record new shortcut for Open Studio")

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: isRecording) { _, recording in
            if recording {
                errorMessage = nil
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    handle(event)
                    return nil
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }
        .onDisappear {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            isRecording = false
        }
    }

    private var currentLegend: some View {
        let modifierGlyphs = KeyGlyphMapping.modifierGlyphs(
            NSEvent.ModifierFlags(rawValue: UInt(modifierRawValue)).intersection(.deviceIndependentFlagsMask)
        )
        let keyGlyph = KeyGlyphMapping.glyph(forKeyCode: UInt16(keyCode), characters: characters)
        return HStack(spacing: 3) {
            ForEach(Array((modifierGlyphs + [keyGlyph]).enumerated()), id: \.offset) { _, glyph in
                keyGlyphView(glyph)
            }
        }
        .foregroundStyle(theme.colors.faint)
    }

    @ViewBuilder
    private func keyGlyphView(_ glyph: KeyGlyph) -> some View {
        switch glyph {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 9, weight: .semibold))
        case .text(let text):
            Text(text)
                .font(.system(size: 9, weight: .semibold))
        }
    }

    private func handle(_ event: NSEvent) {
        guard Thread.isMainThread else { return }
        if event.keyCode == 53 {
            isRecording = false
            return
        }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let eventCharacters = event.charactersIgnoringModifiers ?? ""
        if let conflict = ReservedShortcut.description(command: flags.contains(.command), keyCode: event.keyCode, characters: eventCharacters) {
            errorMessage = conflict
            isRecording = false
            return
        }
        errorMessage = nil
        characters = eventCharacters
        keyCode = Int(AppSettings.normalizedOpenStudioKeyCode(event.keyCode))
        modifierRawValue = Int(flags.rawValue)
        isRecording = false
    }
}
