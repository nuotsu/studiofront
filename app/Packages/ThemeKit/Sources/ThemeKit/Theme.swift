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

    /// Liquid Glass uses macOS's continuous "squircle" corners; Sanity UI uses
    /// plain circular corners to match Sanity Studio's flat chrome.
    public var cornerStyle: RoundedCornerStyle {
        surface.kind == .glass ? .continuous : .circular
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
