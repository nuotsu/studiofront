import AppKit
import Observation
import SwiftUI
import ThemeKit

enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

/// §7.2: the activity-based mode must be labeled honestly as recent edit
/// history, not live presence.
enum PresenceMode: String, CaseIterable, Identifiable, Sendable {
    case realtime
    case activityOnly
    case off

    var id: Self { self }

    var title: String {
        switch self {
        case .realtime: "Live presence"
        case .activityOnly: "Recent activity"
        case .off: "Off"
        }
    }

    var caption: String? {
        switch self {
        case .realtime: nil
        case .activityOnly: "Reflects recent edit history, not who's currently viewing."
        case .off: nil
        }
    }
}

enum MenuBarIconPreference: String, CaseIterable, Identifiable, Sendable {
    case studiofront
    case sanity

    var id: Self { self }

    var title: String {
        switch self {
        case .studiofront: "Studiofront"
        case .sanity: "Sanity"
        }
    }

    var imageName: String {
        switch self {
        case .studiofront: "MenuBarIcon"
        case .sanity: "MenuBarIconSanity"
        }
    }
}

@MainActor
@Observable
final class AppSettings {
    var themePreference: ThemePreference {
        didSet { UserDefaults.standard.set(themePreference.rawValue, forKey: Keys.theme) }
    }

    var appearancePreference: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearancePreference.rawValue, forKey: Keys.appearance)
            // Apply before the next SwiftUI render so theme colors that snapshot
            // against `NSApp.appearance` resolve to the new light/dark immediately.
            AppDelegate.shared?.applyAppearance(appearancePreference)
        }
    }

    var menuBarIconPreference: MenuBarIconPreference {
        didSet { UserDefaults.standard.set(menuBarIconPreference.rawValue, forKey: Keys.menuBarIcon) }
    }

    var showInDock: Bool {
        didSet { UserDefaults.standard.set(showInDock, forKey: Keys.showInDock) }
    }

    var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: Keys.refreshInterval) }
    }

    var hideArchivedProjects: Bool {
        didSet { UserDefaults.standard.set(hideArchivedProjects, forKey: Keys.hideArchivedProjects) }
    }

    // TODO: move to Settings > Advanced once that tab exists (spec §10).
    var presenceMode: PresenceMode {
        didSet { UserDefaults.standard.set(presenceMode.rawValue, forKey: Keys.presenceMode) }
    }

    var openStudioKeyCode: Int {
        didSet { UserDefaults.standard.set(openStudioKeyCode, forKey: Keys.openStudioKeyCode) }
    }

    var openStudioModifierRawValue: Int {
        didSet { UserDefaults.standard.set(openStudioModifierRawValue, forKey: Keys.openStudioModifierRawValue) }
    }

    /// The raw characters captured when this binding was last recorded (empty for the
    /// default Return binding). Persisted so letter/digit rebinds can still render their
    /// correct glyph after a relaunch, when there's no live NSEvent to re-derive it from.
    var openStudioCharacters: String {
        didSet { UserDefaults.standard.set(openStudioCharacters, forKey: Keys.openStudioCharacters) }
    }

    var openStudiofrontKeyCode: Int {
        didSet { UserDefaults.standard.set(openStudiofrontKeyCode, forKey: Keys.openStudiofrontKeyCode) }
    }

    var openStudiofrontModifierRawValue: Int {
        didSet { UserDefaults.standard.set(openStudiofrontModifierRawValue, forKey: Keys.openStudiofrontModifierRawValue) }
    }

    var openStudiofrontCharacters: String {
        didSet { UserDefaults.standard.set(openStudiofrontCharacters, forKey: Keys.openStudiofrontCharacters) }
    }

    var refreshInterval: TimeInterval {
        TimeInterval(max(1, refreshIntervalMinutes) * 60)
    }

    var resolvedTheme: any Theme {
        themePreference.theme
    }

    var openStudioModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(openStudioModifierRawValue))
            .intersection(.deviceIndependentFlagsMask)
    }

    /// Return and keypad Enter are treated as the same key everywhere this binding is read or recorded.
    nonisolated static func normalizedOpenStudioKeyCode(_ keyCode: UInt16) -> UInt16 {
        keyCode == 76 ? 36 : keyCode
    }

    nonisolated static let defaultOpenStudioKeyCode = 36
    nonisolated static let defaultOpenStudioModifierRawValue = 0

    var openStudiofrontModifierFlags: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(openStudiofrontModifierRawValue))
            .intersection(.deviceIndependentFlagsMask)
    }

    /// ⌘⌥⌃S — a system-wide combo, so it needs modifiers that won't collide with
    /// ordinary typing in whatever app happens to be frontmost.
    nonisolated static let defaultOpenStudiofrontKeyCode = 1
    nonisolated static let defaultOpenStudiofrontModifierRawValue = Int(
        NSEvent.ModifierFlags([.command, .option, .control]).rawValue
    )
    nonisolated static let defaultOpenStudiofrontCharacters = "s"

    init(
        themePreference: ThemePreference = .liquidGlass,
        appearancePreference: AppearancePreference = .system,
        menuBarIconPreference: MenuBarIconPreference = .studiofront,
        showInDock: Bool = false,
        refreshIntervalMinutes: Int = 5,
        hideArchivedProjects: Bool = true,
        presenceMode: PresenceMode = .realtime,
        openStudioKeyCode: Int = AppSettings.defaultOpenStudioKeyCode,
        openStudioModifierRawValue: Int = AppSettings.defaultOpenStudioModifierRawValue,
        openStudioCharacters: String = "",
        openStudiofrontKeyCode: Int = AppSettings.defaultOpenStudiofrontKeyCode,
        openStudiofrontModifierRawValue: Int = AppSettings.defaultOpenStudiofrontModifierRawValue,
        openStudiofrontCharacters: String = AppSettings.defaultOpenStudiofrontCharacters
    ) {
        self.themePreference = themePreference
        self.appearancePreference = appearancePreference
        self.menuBarIconPreference = menuBarIconPreference
        self.showInDock = showInDock
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.hideArchivedProjects = hideArchivedProjects
        self.presenceMode = presenceMode
        self.openStudioKeyCode = openStudioKeyCode
        self.openStudioModifierRawValue = openStudioModifierRawValue
        self.openStudioCharacters = openStudioCharacters
        self.openStudiofrontKeyCode = openStudiofrontKeyCode
        self.openStudiofrontModifierRawValue = openStudiofrontModifierRawValue
        self.openStudiofrontCharacters = openStudiofrontCharacters
    }

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        let theme = ThemePreference(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .liquidGlass
        let appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        let menuBarIcon = MenuBarIconPreference(rawValue: defaults.string(forKey: Keys.menuBarIcon) ?? "") ?? .studiofront
        let showInDock = defaults.object(forKey: Keys.showInDock) as? Bool ?? false
        let storedInterval = defaults.object(forKey: Keys.refreshInterval) as? Int
        let refresh = Self.allowedRefreshIntervals.contains(storedInterval ?? -1) ? storedInterval! : 5
        let hideArchivedProjects = defaults.object(forKey: Keys.hideArchivedProjects) as? Bool ?? true
        let presenceMode = PresenceMode(rawValue: defaults.string(forKey: Keys.presenceMode) ?? "") ?? .realtime
        let openStudioKeyCode = defaults.object(forKey: Keys.openStudioKeyCode) as? Int ?? Self.defaultOpenStudioKeyCode
        let openStudioModifierRawValue = defaults.object(forKey: Keys.openStudioModifierRawValue) as? Int ?? Self.defaultOpenStudioModifierRawValue
        let openStudioCharacters = defaults.string(forKey: Keys.openStudioCharacters) ?? ""
        let openStudiofrontKeyCode = defaults.object(forKey: Keys.openStudiofrontKeyCode) as? Int
            ?? Self.defaultOpenStudiofrontKeyCode
        let openStudiofrontModifierRawValue = defaults.object(forKey: Keys.openStudiofrontModifierRawValue) as? Int
            ?? Self.defaultOpenStudiofrontModifierRawValue
        let openStudiofrontCharacters = defaults.string(forKey: Keys.openStudiofrontCharacters)
            ?? Self.defaultOpenStudiofrontCharacters
        return AppSettings(
            themePreference: theme,
            appearancePreference: appearance,
            menuBarIconPreference: menuBarIcon,
            showInDock: showInDock,
            refreshIntervalMinutes: refresh,
            hideArchivedProjects: hideArchivedProjects,
            presenceMode: presenceMode,
            openStudioKeyCode: openStudioKeyCode,
            openStudioModifierRawValue: openStudioModifierRawValue,
            openStudioCharacters: openStudioCharacters,
            openStudiofrontKeyCode: openStudiofrontKeyCode,
            openStudiofrontModifierRawValue: openStudiofrontModifierRawValue,
            openStudiofrontCharacters: openStudiofrontCharacters
        )
    }

    static let allowedRefreshIntervals = [1, 5, 15, 30, 60]

    private enum Keys {
        static let theme = "themePreference"
        static let appearance = "appearancePreference"
        static let menuBarIcon = "menuBarIconPreference"
        static let showInDock = "showInDock"
        static let refreshInterval = "refreshIntervalMinutes"
        static let hideArchivedProjects = "hideArchivedProjects"
        static let presenceMode = "presenceMode"
        static let openStudioKeyCode = "openStudioKeyCode"
        static let openStudioModifierRawValue = "openStudioModifierRawValue"
        static let openStudioCharacters = "openStudioCharacters"
        static let openStudiofrontKeyCode = "openStudiofrontKeyCode"
        static let openStudiofrontModifierRawValue = "openStudiofrontModifierRawValue"
        static let openStudiofrontCharacters = "openStudiofrontCharacters"
    }
}
