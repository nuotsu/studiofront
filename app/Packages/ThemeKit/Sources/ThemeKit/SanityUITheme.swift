import SwiftUI

/// Flat Sanity Studio language. Light tokens from `studiofront-dropdown.html`;
/// dark tokens follow Sanity Studio's dark chrome.
public struct SanityUITheme: Theme, Sendable {
    public init() {}

    public var colors: ColorTokens {
        ColorTokens(
            text: .adaptive(light: Color(hex: "0f1215"), dark: Color(hex: "f1f3f6")),
            sub: .adaptive(light: Color(hex: "6b7280"), dark: Color(hex: "9aa3af")),
            faint: .adaptive(light: Color(hex: "98a0aa"), dark: Color(hex: "6b7280")),
            tagBackground: .adaptive(light: Color(hex: "f1f3f6"), dark: Color(hex: "2a2e36")),
            chipBackground: .adaptive(light: Color(hex: "f7f8fa"), dark: Color(hex: "22262e")),
            chipBorder: .adaptive(light: Color(hex: "dfe1e6"), dark: Color(hex: "3a404a")),
            fieldBackground: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "1a1d24")),
            fieldBorder: .adaptive(light: Color(hex: "d3d7de"), dark: Color(hex: "3a404a")),
            divider: .adaptive(light: Color(hex: "ebedf1"), dark: Color(hex: "2a2e36")),
            segmentBackground: .adaptive(light: Color(hex: "f1f3f6"), dark: Color(hex: "2a2e36")),
            segmentOn: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "3a404a")),
            segmentOnText: .adaptive(light: Color(hex: "0f1215"), dark: Color(hex: "f1f3f6")),
            segmentText: .adaptive(light: Color(hex: "6b7280"), dark: Color(hex: "9aa3af")),
            buttonBackground: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "22262e")),
            buttonText: .adaptive(light: Color(hex: "25313f"), dark: Color(hex: "e5e7eb")),
            primaryBackground: Color(hex: "2276fc"),
            primaryText: Color(hex: "ffffff"),
            ring: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "1a1d24")),
            star: Color(hex: "eab308"),
            copied: Color(hex: "1f9d55"),
            hover: .adaptive(
                light: Color(hex: "f1f3f6"),
                dark: Color.rgba(127 / 255, 133 / 255, 145 / 255, 0.16)
            ),
            selection: .adaptive(
                light: Color(hex: "e8edf5"),
                dark: Color.rgba(127 / 255, 133 / 255, 145 / 255, 0.28)
            ),
            panelFill: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "1a1d24")),
            panelBorder: .adaptive(light: Color(hex: "d9dbe0"), dark: Color(hex: "3a404a"))
        )
    }

    public var typography: TypographyTokens { TypographyTokens() }

    public var metrics: MetricTokens { MetricTokens() }

    public var surface: SurfaceStyle {
        SurfaceStyle(kind: .flat, cornerRadius: 12)
    }
}
