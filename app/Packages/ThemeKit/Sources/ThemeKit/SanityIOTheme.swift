import SwiftUI

/// "Sanity.io": the neutral-gray Studio mockups on sanity.io's homepage
/// (light and dark), with Sanity's brand orange in place of the UI 5 blue.
/// Values are sampled from those mockups.
public struct SanityIOTheme: Theme, Sendable {
    public let colors: ColorTokens
    public let typography: TypographyTokens
    public let metrics: MetricTokens
    public let surface: SurfaceStyle

    /// Brand orange from the Sanity logo mark.
    static let orange = Color(hex: "ff4400")

    public init() {
        // Pane dividers, chip and icon-box outlines.
        let border = Color.adaptive(light: Color(hex: "e2e2e2"), dark: Color(hex: "2f2f2f"))
        // Main pane / list background.
        let backdrop = Color.adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "0d0d0d"))

        colors = ColorTokens(
            // Selected rows and headings.
            text: .adaptive(light: Color(hex: "4a4a4a"), dark: Color(hex: "bbbbbb")),
            // Unselected rows, column headers, field labels.
            sub: .adaptive(light: Color(hex: "797979"), dark: Color(hex: "7e7e7e")),
            // Field placeholder.
            faint: .adaptive(light: Color(hex: "a6a6a6"), dark: Color(hex: "616161")),
            // Selected tab ("Editorial").
            tagBackground: .adaptive(light: Color(hex: "ededed"), dark: Color(hex: "252525")),
            chipBackground: .adaptive(light: Color(hex: "f5f5f5"), dark: Color(hex: "181818")),
            chipBorder: border,
            divider: border,
            buttonBackground: backdrop,
            buttonText: .adaptive(light: Color(hex: "4a4a4a"), dark: Color(hex: "bbbbbb")),
            primaryBackground: Self.orange,
            primaryText: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "0d0d0d")),
            ring: backdrop,
            // Draft dot / proofreading icon.
            star: .adaptive(light: Color(hex: "de8600"), dark: Color(hex: "ffba00")),
            copied: .adaptive(light: Color(hex: "01794f"), dark: Color(hex: "0ff0a1")),
            hover: .adaptive(light: Color(hex: "f5f5f5"), dark: Color(hex: "1a1a1a")),
            // Selected sidebar item / document row.
            selection: .adaptive(light: Color(hex: "ededed"), dark: Color(hex: "252525")),
            panelFill: backdrop,
            panelBorder: border,
            // Left nav column: one step off the main pane.
            sidebarFill: .adaptive(light: Color(hex: "fbfbfb"), dark: Color(hex: "121212")),
            fieldBackground: backdrop,
            fieldBorder: .adaptive(light: Color(hex: "ededed"), dark: Color(hex: "272727")),
            focusRing: Self.orange,
            // Selected "Battery life" row: pure white on dark; near-black on light.
            highlightedTitle: .adaptive(light: Color(hex: "0b0b0b"), dark: Color(hex: "ffffff")),
            caret: Self.orange
        )
        typography = TypographyTokens()
        metrics = MetricTokens()
        surface = SurfaceStyle(kind: .flat)
    }

    public func legendForeground(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "7e7e7e") : Color(hex: "797979")
    }

    public func legendBorder(for colorScheme: ColorScheme) -> Color {
        colorScheme == .dark ? Color(hex: "2a2a2a") : Color(hex: "e3e3e3")
    }
}
