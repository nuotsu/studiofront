import AppKit
import SwiftUI

struct MenuBarIconLabel: View {
    var preference: MenuBarIconPreference

    var body: some View {
        Group {
            if let image = Self.menuBarStatusImage(named: preference.imageName) {
                Image(nsImage: image)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityLabel("Studiofront")
    }

    private static let statusImageCache = NSCache<NSString, NSImage>()

    /// Template glyph sized to menu-bar height, preserving the SVG aspect ratio.
    static func menuBarStatusImage(named name: String) -> NSImage? {
        let key = name as NSString
        if let cached = statusImageCache.object(forKey: key) {
            return cached
        }

        guard let source = NSImage(named: name) else { return nil }
        let height: CGFloat = 16
        let aspect = source.size.width / max(source.size.height, 1)
        let size = NSSize(width: (height * aspect).rounded(), height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Studiofront"
        statusImageCache.setObject(image, forKey: key)
        return image
    }
}
