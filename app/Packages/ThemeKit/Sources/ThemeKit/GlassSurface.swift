import AppKit
import SwiftUI

/// macOS 26 `NSGlassEffectView` chrome.
/// Installed as a background: `hitTest` returns nil so SwiftUI controls stay clickable.
public struct GlassSurface: NSViewRepresentable {
    var cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    public init(cornerRadius: CGFloat) {
        self.cornerRadius = cornerRadius
    }

    public func makeNSView(context: Context) -> PassthroughGlassView {
        let container = PassthroughGlassView()
        container.autoresizingMask = [.width, .height]
        installChrome(in: container)
        return container
    }

    public func updateNSView(_ container: PassthroughGlassView, context: Context) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        // Recreate chrome on light/dark flips — mutating `appearance` on an
        // existing `NSGlassEffectView` crossfades; a fresh view snaps.
        if container.appliedColorScheme != colorScheme || container.chromeView == nil {
            installChrome(in: container)
            return
        }

        guard let glass = container.chromeView as? NSGlassEffectView,
              container.appliedCornerRadius != cornerRadius
        else { return }
        container.appliedCornerRadius = cornerRadius
        glass.cornerRadius = cornerRadius
    }

    private func installChrome(in container: PassthroughGlassView) {
        container.chromeView?.removeFromSuperview()

        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        let glass = NSGlassEffectView(frame: container.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.cornerRadius = cornerRadius
        glass.style = .regular
        glass.appearance = appearance

        container.appearance = appearance
        container.addSubview(glass)
        container.chromeView = glass
        container.appliedCornerRadius = cornerRadius
        container.appliedColorScheme = colorScheme
    }
}

public final class PassthroughGlassView: NSView {
    var chromeView: NSView?
    var appliedCornerRadius: CGFloat?
    var appliedColorScheme: ColorScheme?

    public override func hitTest(_ point: NSPoint) -> NSView? { nil }

    public override func layout() {
        super.layout()
        chromeView?.frame = bounds
    }
}

/// Theme-aware popover chrome: glass material, or a flat card when Reduce Transparency
/// is on or the active theme is flat.
public struct ThemedSurface: View {
    @Environment(\.studioTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init() {}

    public var body: some View {
        let metrics = theme.metrics
        let colors = theme.colors
        let useGlass = theme.surface.kind == .glass && !reduceTransparency

        ZStack {
            if useGlass {
                GlassSurface(cornerRadius: metrics.panelCornerRadius)
                    .allowsHitTesting(false)
                    // Remount with the scheme so glass/tokens don't crossfade.
                    .id(colorScheme)
            } else {
                RoundedRectangle(cornerRadius: theme.cornerRadius(metrics.panelCornerRadius), style: theme.cornerStyle)
                    .fill(colors.panelFill)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(colors.panelBorder)
                .frame(height: 1)
        }
    }
}
