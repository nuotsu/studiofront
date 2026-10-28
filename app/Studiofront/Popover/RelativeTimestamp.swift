import Foundation
import SwiftUI

enum RelativeTimestamp {
    static func string(from date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 45 { return "just now" }
        if interval < 3600 { return "\(max(1, Int((interval / 60).rounded())))m ago" }
        if interval < 24 * 3600 { return "\(max(1, Int((interval / 3600).rounded())))h ago" }
        let days = Int((interval / (24 * 3600)).rounded())
        if days <= 1 { return "yesterday" }
        if days < 7 { return "\(days)d ago" }
        if days < 31 { return "\(max(1, days / 7))wk ago" }
        if days < 365 { return "\(max(1, days / 30))mo ago" }
        return "\(max(1, days / 365))yr ago"
    }
}

enum PresenceSwatch {
    /// FNV-1a over the id's UTF-8 bytes. `Hasher` is randomly seeded per
    /// launch, which gave the same teammate a different color every relaunch.
    static func color(for id: String) -> Color {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in id.utf8 {
            hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3
        }
        let hue = Double(hash % 360) / 360.0
        return Color(hue: hue, saturation: 0.55, brightness: 0.72)
    }
}
