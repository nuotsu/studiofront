import SwiftUI

/// Native macOS 26 materials. Token values come from `studiofront-dropdown.html`
/// (dark glass) plus a light-appearance counterpart.
public struct LiquidGlassTheme: Theme, Sendable {
    public init() {}

    public var colors: ColorTokens {
        ColorTokens(
            text: .glassInk(lightAlpha: 0.92, darkAlpha: 0.96),
            sub: .glassInk(lightAlpha: 0.55, darkAlpha: 0.58),
            faint: .glassInk(lightAlpha: 0.40, darkAlpha: 0.40),
            tagBackground: .glassInk(lightAlpha: 0.08, darkAlpha: 0.10),
            chipBackground: .glassInk(lightAlpha: 0.06, darkAlpha: 0.09),
            chipBorder: .glassInk(lightAlpha: 0.14, darkAlpha: 0.16),
            fieldBackground: .glassInk(lightAlpha: 0.08, darkAlpha: 0.10),
            fieldBorder: .glassInk(lightAlpha: 0.16, darkAlpha: 0.18),
            divider: .glassInk(lightAlpha: 0.10, darkAlpha: 0.11),
            segmentBackground: .glassInk(lightAlpha: 0.08, darkAlpha: 0.10),
            segmentOn: .adaptive(light: .rgba(0.10, 0.11, 0.13, 0.90), dark: .rgba(1, 1, 1, 0.92)),
            segmentOnText: .adaptive(light: .rgba(1, 1, 1, 0.96), dark: Color(hex: "191b21")),
            segmentText: .glassInk(lightAlpha: 0.55, darkAlpha: 0.62),
            buttonBackground: .glassInk(lightAlpha: 0.08, darkAlpha: 0.10),
            buttonText: .glassInk(lightAlpha: 0.80, darkAlpha: 0.88),
            // oklch(0.78 0.13 245) ≈ #71B0FC
            primaryBackground: Color(hex: "71B0FC"),
            primaryText: Color(hex: "10161f"),
            ring: .adaptive(light: .rgba(1, 1, 1, 0.92), dark: Color(hex: "22242a", opacity: 0.92)),
            star: .adaptive(light: Color(hex: "d4a017"), dark: Color(hex: "f2c14a")),
            copied: Color(hex: "1f9d55"),
            hover: Color.rgba(127 / 255, 133 / 255, 145 / 255, 0.16),
            selection: Color.rgba(127 / 255, 133 / 255, 145 / 255, 0.28),
            panelFill: .adaptive(
                light: Color(hex: "f4f5f7", opacity: 0.92),
                dark: Color(hex: "1c1e24", opacity: 0.88)
            ),
            panelBorder: .glassInk(lightAlpha: 0.14, darkAlpha: 0.16)
        )
    }

    public var typography: TypographyTokens { TypographyTokens() }

    public var metrics: MetricTokens { MetricTokens() }

    public var surface: SurfaceStyle {
        SurfaceStyle(kind: .glass, cornerRadius: 12)
    }
}
