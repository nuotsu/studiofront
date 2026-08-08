import AppKit
import SwiftUI

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

    /// Appearance-adaptive color. Resolves against the view's effective appearance.
    static func adaptive(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }

    /// White-on-dark / black-on-light translucent ink used by Liquid Glass.
    static func glassInk(lightAlpha: Double, darkAlpha: Double) -> Color {
        .adaptive(
            light: .rgba(0, 0, 0, lightAlpha),
            dark: .rgba(1, 1, 1, darkAlpha)
        )
    }
}

