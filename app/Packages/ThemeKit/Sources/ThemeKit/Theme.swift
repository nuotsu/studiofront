import SwiftUI

public protocol Theme: Sendable {
    var colors: ColorTokens { get }
    var typography: TypographyTokens { get }
    var metrics: MetricTokens { get }
    var surface: SurfaceStyle { get }
    /// Keycap legend foreground. Declared as requirements (not only extension
    /// methods) so a theme can override the defaults through `any Theme`.
    func legendForeground(for colorScheme: ColorScheme) -> Color
    /// Keycap legend border.
    func legendBorder(for colorScheme: ColorScheme) -> Color
}

extension Theme {
    /// The Sanity themes are a flat, non-glass design language and use a fixed
    /// 0.1875rem (3pt) corner radius instead of the Liquid Glass metrics.
    public func cornerRadius(_ glassValue: CGFloat) -> CGFloat {
        surface.kind == .glass ? glassValue : 3
    }

    /// Plain circular corners to match Sanity Studio's flat chrome.
    public var cornerStyle: RoundedCornerStyle {
        surface.kind == .glass ? .continuous : .circular
    }

    /// Keycap legend foreground — resolved from SwiftUI `colorScheme` because
    /// `Color.adaptive` reads `NSApp.appearance`, which can disagree with the
    /// panel's effective scheme.
    public func legendForeground(for colorScheme: ColorScheme) -> Color {
        switch (surface.kind, colorScheme) {
        case (.glass, .dark):
            return .rgba(1, 1, 1, 0.55)
        case (.glass, .light):
            return .rgba(0, 0, 0, 0.40)
        case (.flat, .dark):
            return Color(hex: "9499ad")
        case (.flat, .light):
            return Color(hex: "727892")
        default:
            return colors.faint
        }
    }

    /// Keycap legend border — same `colorScheme` resolution as `legendForeground`.
    public func legendBorder(for colorScheme: ColorScheme) -> Color {
        switch (surface.kind, colorScheme) {
        case (.glass, .dark):
            return .rgba(1, 1, 1, 0.22)
        case (.glass, .light):
            return .rgba(0, 0, 0, 0.14)
        // Sanity's <kbd> outline on sanity.io/manage; light mirrors it with gray-200.
        case (.flat, .dark):
            return Color(hex: "2a2d3f")
        case (.flat, .light):
            return Color(hex: "e3e4e8")
        default:
            return colors.chipBorder
        }
    }
}

public enum ThemePreference: String, CaseIterable, Identifiable, Sendable {
    case liquidGlass
    /// Raw value kept from the former "Sanity UI" name so saved settings carry over.
    case studio = "sanityUI"
    case sanityIO

    public var id: Self { self }

    public var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .studio: "Studio"
        case .sanityIO: "Sanity.io"
        }
    }

    public var theme: any Theme {
        switch self {
        case .liquidGlass: LiquidGlassTheme()
        case .studio: SanityStudioTheme()
        case .sanityIO: SanityIOTheme()
        }
    }

    /// The theme resolved for a fixed light or dark scheme, independent of
    /// the app's current appearance (used by the Settings previews).
    public func theme(for colorScheme: ColorScheme) -> any Theme {
        AppearanceOverride.$isDark.withValue(colorScheme == .dark) { theme }
    }
}

private struct StudioThemeKey: EnvironmentKey {
    static let defaultValue: any Theme = LiquidGlassTheme()
}

extension EnvironmentValues {
    public var studioTheme: any Theme {
        get { self[StudioThemeKey.self] }
        set { self[StudioThemeKey.self] = newValue }
    }
}

extension View {
    public func studioTheme(_ theme: any Theme) -> some View {
        environment(\.studioTheme, theme)
    }
}
