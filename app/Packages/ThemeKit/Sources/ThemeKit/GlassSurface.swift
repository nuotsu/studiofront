import AppKit
import SwiftUI

/// Prefers macOS 26 `NSGlassEffectView`, falls back to `NSVisualEffectView`.
/// Installed as a background: `hitTest` returns nil so SwiftUI controls stay clickable.
public struct GlassSurface: NSViewRepresentable {
    var cornerRadius: CGFloat
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode

    public init(
        cornerRadius: CGFloat,
        material: NSVisualEffectView.Material = .popover,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    ) {
        self.cornerRadius = cornerRadius
        self.material = material
        self.blendingMode = blendingMode
    }

    public func makeNSView(context: Context) -> PassthroughGlassView {
        let container = PassthroughGlassView()
        container.autoresizingMask = [.width, .height]

        let chrome: NSView
        if let glassClass = NSClassFromString("NSGlassEffectView") as? NSView.Type {
            let glass = glassClass.init(frame: .zero)
            glass.autoresizingMask = [.width, .height]
            glass.wantsLayer = true
            Self.applyCornerRadius(cornerRadius, to: glass)
            Self.applyDefaultGlassStyle(to: glass)
            chrome = glass
        } else {
            let view = NSVisualEffectView()
            view.autoresizingMask = [.width, .height]
            view.wantsLayer = true
            view.layerContentsRedrawPolicy = .onSetNeedsDisplay
            view.material = material
            view.blendingMode = blendingMode
            view.state = .active
            Self.applyCornerRadius(cornerRadius, to: view)
            chrome = view
        }

        chrome.frame = container.bounds
        container.addSubview(chrome)
        container.chromeView = chrome
        container.appliedCornerRadius = cornerRadius
        container.appliedMaterial = material
        container.appliedBlendingMode = blendingMode
        return container
    }

    public func updateNSView(_ container: PassthroughGlassView, context: Context) {
        guard let chrome = container.chromeView else { return }

        if container.appliedCornerRadius != cornerRadius {
            container.appliedCornerRadius = cornerRadius
            Self.applyCornerRadius(cornerRadius, to: chrome)
        }

        if chrome.className == "NSGlassEffectView" { return }

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

    private static func applyCornerRadius(_ radius: CGFloat, to view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = radius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = radius > 0
    }

    private static func applyDefaultGlassStyle(to glassView: NSView) {
        let styleSelector = NSSelectorFromString("setStyle:")
        if glassView.responds(to: styleSelector),
           let implementation = glassView.method(for: styleSelector)
        {
            typealias StyleSetter = @convention(c) (AnyObject, Selector, Int) -> Void
            let setter = unsafeBitCast(implementation, to: StyleSetter.self)
            setter(glassView, styleSelector, 0)
        }
    }
}

public final class PassthroughGlassView: NSView {
    var chromeView: NSView?
    var appliedCornerRadius: CGFloat?
    var appliedMaterial: NSVisualEffectView.Material?
    var appliedBlendingMode: NSVisualEffectView.BlendingMode?

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
            } else {
                RoundedRectangle(cornerRadius: metrics.panelCornerRadius, style: .continuous)
                    .fill(colors.panelFill)
            }

            RoundedRectangle(cornerRadius: metrics.panelCornerRadius, style: .continuous)
                .strokeBorder(colors.panelBorder, lineWidth: 1)
        }
    }
}
