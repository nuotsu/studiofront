import SwiftUI

public protocol Theme: Sendable {
    var colors: ColorTokens { get }
    var typography: TypographyTokens { get }
    var metrics: MetricTokens { get }
    var surface: SurfaceStyle { get }
}

extension Theme {
    /// Sanity UI is a flat, non-glass design language and uses its own fixed
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
            return Color(hex: "9aa3af")
        case (.flat, .light):
            return Color(hex: "98a0aa")
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
        case (.flat, .dark):
            return Color(hex: "4b5563")
        case (.flat, .light):
            return Color(hex: "dfe1e6")
        default:
            return colors.chipBorder
        }
    }

    /// Widget outline — resolved from SwiftUI `colorScheme` for the same reason
    /// as legend colors.
    public func panelBorder(for colorScheme: ColorScheme) -> Color {
        switch surface.kind {
        case .glass:
            return colorScheme == .dark ? .rgba(1, 1, 1, 0.16) : .rgba(0, 0, 0, 0.14)
        case .flat:
            return colorScheme == .dark ? Color(hex: "3a404a") : Color(hex: "d9dbe0")
        }
    }
}

public enum ThemePreference: String, CaseIterable, Identifiable, Sendable {
    case liquidGlass
    case sanityUI

    public var id: Self { self }

    public var title: String {
        switch self {
        case .liquidGlass: "Liquid Glass"
        case .sanityUI: "Sanity UI"
        }
    }

    public var theme: any Theme {
        switch self {
        case .liquidGlass: LiquidGlassTheme()
        case .sanityUI: SanityUITheme()
        }
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
