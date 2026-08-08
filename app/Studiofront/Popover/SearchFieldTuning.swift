import AppKit
import SwiftUI

/// Hides the AppKit focus ring on the nearby SwiftUI `TextField`.
struct SearchFieldTuning: NSViewRepresentable {
    func makeNSView(context: Context) -> TunerView {
        let view = TunerView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: TunerView, context: Context) {
        nsView.applyTuning()
    }

    final class TunerView: NSView {
        private weak var tunedField: NSTextField?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tunedField = nil
            applyTuning()
        }

        func applyTuning() {
            guard let field = resolvedField() else { return }
            field.focusRingType = .none
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
        }

        private func resolvedField() -> NSTextField? {
            if let tunedField, let window, tunedField.window === window {
                return tunedField
            }
            let field = Self.nearestTextField(from: self)
            tunedField = field
            return field
        }

        private static func nearestTextField(from view: NSView) -> NSTextField? {
            var node: NSView? = view.superview
            while let current = node {
                if let field = current as? NSTextField { return field }
                if let field = current.subviews.compactMap({ $0 as? NSTextField }).first { return field }
                for sibling in current.subviews where sibling !== view {
                    if let field = findTextField(in: sibling) { return field }
                }
                node = current.superview
            }
            return nil
        }

        private static func findTextField(in root: NSView) -> NSTextField? {
            if let field = root as? NSTextField { return field }
            for child in root.subviews {
                if let field = findTextField(in: child) { return field }
            }
            return nil
        }
    }
}
