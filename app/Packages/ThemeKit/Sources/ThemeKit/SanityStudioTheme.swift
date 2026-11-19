import SwiftUI

/// "Studio": flat Sanity Studio language, using the Sanity UI 5 palette
/// (`@sanity/ui` 5.x `styles.css` primitives and semantic tokens).
/// Comments name the UI 5 semantic token each color resolves to.
public struct SanityStudioTheme: Theme, Sendable {
    public let colors: ColorTokens
    public let typography: TypographyTokens
    public let metrics: MetricTokens
    public let surface: SurfaceStyle

    public init() {
        // One solid border for dividers, chips, panels, fields and the footer
        // icons (as in the Sanity.io theme): the text input outline from
        // sanity.io/manage. UI 5's translucent --separator-low read too dark
        // on its own and lighter wherever it stacked on a system separator.
        let border = Color.adaptive(light: Color(hex: "dcdee5"), dark: Color(hex: "333749"))

        colors = ColorTokens(
            // --foreground-high: gray-800 / gray-200
            text: .adaptive(light: Color(hex: "252837"), dark: Color(hex: "e3e4e8")),
            // --foreground-low: gray-600 / gray-400
            sub: .adaptive(light: Color(hex: "515870"), dark: Color(hex: "9499ad")),
            // --inert-foreground: gray-400 / gray-500
            faint: .adaptive(light: Color(hex: "9499ad"), dark: Color(hex: "727892")),
            // --background-high: gray-100 / gray-900
            tagBackground: .adaptive(light: Color(hex: "eeeef1"), dark: Color(hex: "1b1d27")),
            // --background-low: gray-50 / gray-950
            chipBackground: .adaptive(light: Color(hex: "f6f6f8"), dark: Color(hex: "13141b")),
            chipBorder: border,
            divider: border,
            // --backdrop: white / black
            buttonBackground: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "13141b")),
            // --foreground-high
            buttonText: .adaptive(light: Color(hex: "252837"), dark: Color(hex: "e3e4e8")),
            // UI 5 selected / focus blue: blue-600 / blue-400
            primaryBackground: .adaptive(light: Color(hex: "4043e7"), dark: Color(hex: "7595ff")),
            // white / black on the selected blue
            primaryText: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "13141b")),
            // --backdrop
            ring: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "13141b")),
            // yellow-500 / yellow-400
            star: .adaptive(light: Color(hex: "d28a04"), dark: Color(hex: "f9bc15")),
            // green-600 / green-400
            copied: .adaptive(light: Color(hex: "01794f"), dark: Color(hex: "0ff0a1")),
            // --active-background-normal: gray-100 / gray-900
            hover: .adaptive(light: Color(hex: "eeeef1"), dark: Color(hex: "1b1d27")),
            // One step stronger than hover: gray-200 / gray-800
            selection: .adaptive(light: Color(hex: "e3e4e8"), dark: Color(hex: "252837")),
            // --backdrop
            panelFill: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "13141b")),
            panelBorder: border,
            // sanity.io/manage: sidebar #0d0e12 beside the #13141b main area.
            // Light mirrors it one step off white: gray-50.
            sidebarFill: .adaptive(light: Color(hex: "f6f6f8"), dark: Color(hex: "0d0e12")),
            // Text input, from sanity.io/manage: --backdrop fill, 1px border, blue focus ring.
            fieldBackground: .adaptive(light: Color(hex: "ffffff"), dark: Color(hex: "13141b")),
            fieldBorder: border,
            focusRing: Color(hex: "556bfc")
        )
        typography = TypographyTokens()
        metrics = MetricTokens()
        surface = SurfaceStyle(kind: .flat)
    }
}
