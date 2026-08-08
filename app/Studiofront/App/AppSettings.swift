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

    var refreshIntervalMinutes: Int {
        didSet { UserDefaults.standard.set(refreshIntervalMinutes, forKey: Keys.refreshInterval) }
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
        refreshIntervalMinutes: Int = 5
    ) {
        self.themePreference = themePreference
        self.appearancePreference = appearancePreference
        self.refreshIntervalMinutes = refreshIntervalMinutes
    }

    static func load() -> AppSettings {
        let defaults = UserDefaults.standard
        let theme = ThemePreference(rawValue: defaults.string(forKey: Keys.theme) ?? "") ?? .liquidGlass
        let appearance = AppearancePreference(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        let storedInterval = defaults.object(forKey: Keys.refreshInterval) as? Int
        let refresh = Self.allowedRefreshIntervals.contains(storedInterval ?? -1) ? storedInterval! : 5
        return AppSettings(
            themePreference: theme,
            appearancePreference: appearance,
            refreshIntervalMinutes: refresh
        )
    }

    static let allowedRefreshIntervals = [1, 5, 15, 30, 60]

    private enum Keys {
        static let theme = "themePreference"
        static let appearance = "appearancePreference"
        static let refreshInterval = "refreshIntervalMinutes"
    }
}
