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

@MainActor
@Observable
final class AppSettings {
    var themePreference: ThemePreference {
        didSet { UserDefaults.standard.set(themePreference.rawValue, forKey: Keys.theme) }
    }

    var appearancePreference: AppearancePreference {
        didSet { UserDefaults.standard.set(appearancePreference.rawValue, forKey: Keys.appearance) }
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

    var refreshInterval: TimeInterval {
        TimeInterval(max(1, refreshIntervalMinutes) * 60)
    }

    var resolvedTheme: any Theme {
        themePreference.theme
    }

    init(
        themePreference: ThemePreference = .liquidGlass,
        appearancePreference: AppearancePreference = .system,
        showInDock: Bool = false,
        refreshIntervalMinutes: Int = 5,
        hideArchivedProjects: Bool = true
    ) {
        self.themePreference = themePreference
        self.appearancePreference = appearancePreference
        self.showInDock = showInDock
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.hideArchivedProjects = hideArchivedProjects
    }

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        let theme = ThemePreference(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .liquidGlass
        let appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        let showInDock = defaults.object(forKey: Keys.showInDock) as? Bool ?? false
        let storedInterval = defaults.object(forKey: Keys.refreshInterval) as? Int
        let refresh = Self.allowedRefreshIntervals.contains(storedInterval ?? -1) ? storedInterval! : 5
        let hideArchivedProjects = defaults.object(forKey: Keys.hideArchivedProjects) as? Bool ?? true
        return AppSettings(
            themePreference: theme,
            appearancePreference: appearance,
            showInDock: showInDock,
            refreshIntervalMinutes: refresh,
            hideArchivedProjects: hideArchivedProjects
        )
    }

    static let allowedRefreshIntervals = [1, 5, 15, 30, 60]

    private enum Keys {
        static let theme = "themePreference"
        static let appearance = "appearancePreference"
        static let showInDock = "showInDock"
        static let refreshInterval = "refreshIntervalMinutes"
        static let hideArchivedProjects = "hideArchivedProjects"
    }
}
