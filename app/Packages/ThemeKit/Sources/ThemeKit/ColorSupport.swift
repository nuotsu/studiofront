import AppKit
import SwiftUI

/// Forces `Color.adaptive` to one side while a theme is built, so a theme's
/// light and dark palettes can be read regardless of the app appearance.
enum AppearanceOverride {
    @TaskLocal static var isDark: Bool?
}

extension Color {
    init(hex: String, opacity: Double = 1) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        let red, green, blue: Double
        switch cleaned.count {
        case 6:
            red = Double((value >> 16) & 0xFF) / 255
            green = Double((value >> 8) & 0xFF) / 255
            blue = Double(value & 0xFF) / 255
        default:
            red = 0
            green = 0
            blue = 0
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    static func rgba(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    /// Appearance-adaptive color.
    ///
    /// Resolves to a discrete light/dark `Color` against the current app
    /// appearance. Dynamic `NSColor(name:)` providers crossfade when light/dark
    /// flips; a plain `Color` swapped via appearance remounts snaps instead.
    /// `AppearanceOverride.isDark`, when set, wins over the app appearance.
    static func adaptive(light: Color, dark: Color) -> Color {
        if let isDark = AppearanceOverride.isDark {
            return isDark ? dark : light
        }
        let appearance = NSApp.appearance ?? NSApp.effectiveAppearance
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? dark : light
    }

    /// White-on-dark / black-on-light translucent ink used by Liquid Glass.
    static func glassInk(lightAlpha: Double, darkAlpha: Double) -> Color {
        .adaptive(
            light: .rgba(0, 0, 0, lightAlpha),
            dark: .rgba(1, 1, 1, darkAlpha)
        )
    }
}

