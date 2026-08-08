import SwiftUI

public protocol Theme: Sendable {
    var colors: ColorTokens { get }
    var typography: TypographyTokens { get }
    var metrics: MetricTokens { get }
    var surface: SurfaceStyle { get }
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
