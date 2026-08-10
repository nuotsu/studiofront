import AppKit
import SwiftUI

/// Prefers macOS 26 `NSGlassEffectView`, falls back to `NSVisualEffectView`.
/// Installed as a background: `hitTest` returns nil so SwiftUI controls stay clickable.
public struct GlassSurface: NSViewRepresentable {
    var cornerRadius: CGFloat
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    /// Skips `NSGlassEffectView` even when available. That view's "Liquid Glass"
    /// rendering has its own baked-in lift/rounding/brightening independent of
    /// `cornerRadius`, which looks wrong for a plain flat blur strip — use this
    /// for a predictable, ordinary frosted-glass look instead.
    var preferSimpleMaterial: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(
        cornerRadius: CGFloat,
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        preferSimpleMaterial: Bool = false
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.blendingMode = blendingMode
        self.preferSimpleMaterial = preferSimpleMaterial
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

        guard let chrome = container.chromeView else { return }

        if let glass = chrome as? NSGlassEffectView {
            if container.appliedCornerRadius != cornerRadius {
                container.appliedCornerRadius = cornerRadius
                glass.cornerRadius = cornerRadius
            }
            return
        }

        if container.appliedCornerRadius != cornerRadius {
            container.appliedCornerRadius = cornerRadius
            Self.applyCornerRadius(cornerRadius, to: chrome)
        }

        guard let visualEffect = chrome as? NSVisualEffectView else { return }
        guard container.appliedMaterial != material
            || container.appliedBlendingMode != blendingMode
            || visualEffect.state != .active
        else { return }

        container.appliedMaterial = material
        container.appliedBlendingMode = blendingMode
        visualEffect.material = material
        visualEffect.blendingMode = blendingMode
        visualEffect.state = .active
        visualEffect.needsDisplay = true
    }

    private func installChrome(in container: PassthroughGlassView) {
        container.chromeView?.removeFromSuperview()

        let appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        let chrome: NSView
        if !preferSimpleMaterial {
            let glass = NSGlassEffectView(frame: .zero)
            glass.autoresizingMask = [.width, .height]
            glass.cornerRadius = cornerRadius
            glass.style = .regular
            glass.appearance = appearance
            chrome = glass
        } else {
            let view = NSVisualEffectView()
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
            view.layerContentsRedrawPolicy = .onSetNeedsDisplay
            view.material = material
            view.blendingMode = blendingMode
            view.state = .active
            view.appearance = appearance
            Self.applyCornerRadius(cornerRadius, to: view)
            chrome = view
        }

        chrome.frame = container.bounds
        container.appearance = appearance
        container.addSubview(chrome)
        container.chromeView = chrome
        container.appliedCornerRadius = cornerRadius
        container.appliedMaterial = material
        container.appliedBlendingMode = blendingMode
        container.appliedColorScheme = colorScheme
    }

    private static func applyCornerRadius(_ radius: CGFloat, to view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = radius > 0
    }
}

public final class PassthroughGlassView: NSView {
    var chromeView: NSView?
    var appliedCornerRadius: CGFloat?
    var appliedMaterial: NSVisualEffectView.Material?
    var appliedBlendingMode: NSVisualEffectView.BlendingMode?
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
