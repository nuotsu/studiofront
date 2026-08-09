import Foundation
import Observation
import SwiftUI

enum SettingsSearchTarget: String, Hashable, CaseIterable {
    case showInDock
    case refreshInterval
    case hideArchivedProjects
    case theme
    case appearance
    case accountIdentity
    case signOut
    case cliLogin
    case personalToken
    case keybindingsOverview
    case openStudioShortcut
    case openStudiofrontShortcut
}

struct SettingsSearchItem: Identifiable, Hashable {
    var id: String { target.rawValue }
    var title: String
    var keywords: [String]
    var pane: SettingsPane
    var target: SettingsSearchTarget
    var systemImage: String
}

enum SettingsSearchIndex {
    static let all: [SettingsSearchItem] = [
        SettingsSearchItem(
            title: "Show in Dock",
            keywords: ["dock", "show", "icon", "menubar", "menu bar"],
            pane: .general,
            target: .showInDock,
            systemImage: "dock.rectangle"
        ),
        SettingsSearchItem(
            title: "Refresh interval",
            keywords: ["refresh", "interval", "sync", "minutes"],
            pane: .general,
            target: .refreshInterval,
            systemImage: "arrow.clockwise"
        ),
        SettingsSearchItem(
            title: "Hide archived projects",
            keywords: ["archive", "archived", "hide", "disabled"],
            pane: .general,
            target: .hideArchivedProjects,
            systemImage: "archivebox"
        ),
        SettingsSearchItem(
            title: "Theme",
            keywords: ["theme", "liquid glass", "sanity ui"],
            pane: .appearance,
            target: .theme,
            systemImage: "paintpalette"
        ),
        SettingsSearchItem(
            title: "Appearance",
            keywords: ["appearance", "light", "dark", "system"],
            pane: .appearance,
            target: .appearance,
            systemImage: "circle.lefthalf.filled"
        ),
        SettingsSearchItem(
            title: "Account",
            keywords: ["account", "identity", "user", "email", "profile"],
            pane: .account,
            target: .accountIdentity,
            systemImage: "person.crop.circle"
        ),
        SettingsSearchItem(
            title: "Sign Out",
            keywords: ["sign out", "logout", "disconnect"],
            pane: .account,
            target: .signOut,
            systemImage: "rectangle.portrait.and.arrow.right"
        ),
        SettingsSearchItem(
            title: "Sanity CLI",
            keywords: ["cli", "config", "login", "sanity login", "config.json"],
            pane: .account,
            target: .cliLogin,
            systemImage: "terminal"
        ),
        SettingsSearchItem(
            title: "Personal token",
            keywords: ["token", "api", "manual", "key", "personal"],
            pane: .account,
            target: .personalToken,
            systemImage: "key"
        ),
        SettingsSearchItem(
            title: "Keybindings",
            keywords: ["keybindings", "shortcuts", "keyboard", "hotkeys"],
            pane: .keybindings,
            target: .keybindingsOverview,
            systemImage: "keyboard"
        ),
        SettingsSearchItem(
            title: "Open Studio shortcut",
            keywords: ["open studio", "return", "enter", "rebind", "record"],
            pane: .keybindings,
            target: .openStudioShortcut,
            systemImage: "keyboard"
        ),
        SettingsSearchItem(
            title: "Open Studiofront shortcut",
            keywords: ["open studiofront", "global", "hotkey", "summon", "rebind", "record"],
            pane: .keybindings,
            target: .openStudiofrontShortcut,
            systemImage: "keyboard"
        ),
    ]

    static func matches(_ query: String) -> [SettingsSearchItem] {
        let needle = normalize(query)
        guard !needle.isEmpty else { return [] }
        return all.filter { item in
            let fields = [item.title, item.pane.title] + item.keywords
            return fields.contains { normalize($0).contains(needle) }
        }
    }

    private static func normalize(_ string: String) -> String {
        string.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

@MainActor
@Observable
final class SettingsSearchState {
    var highlightedTarget: SettingsSearchTarget?

    private var clearTask: Task<Void, Never>?

    func highlight(_ target: SettingsSearchTarget) {
        highlightedTarget = target
        clearTask?.cancel()
        clearTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            if highlightedTarget == target {
                highlightedTarget = nil
            }
        }
    }
}

struct SettingsHighlightModifier: ViewModifier {
    var target: SettingsSearchTarget
    @Environment(SettingsSearchState.self) private var search

    func body(content: Content) -> some View {
        let active = search.highlightedTarget == target
        content
            .id(target)
            .listRowBackground(active ? Color.accentColor.opacity(0.16) : nil)
            .animation(.easeInOut(duration: 0.2), value: active)
    }
}

extension View {
    func settingsHighlight(_ target: SettingsSearchTarget) -> some View {
        modifier(SettingsHighlightModifier(target: target))
    }
}
