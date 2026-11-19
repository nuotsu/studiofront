import AppKit
import SwiftUI

/// Hides the AppKit focus ring on the nearby SwiftUI `TextField`, and tints
/// its caret when the theme asks for one.
struct SearchFieldTuning: NSViewRepresentable {
    /// Insertion point color; nil keeps the system caret.
    var caretColor: Color?
    /// Passed only so a focus change re-runs `updateNSView`, which re-tints
    /// the field editor AppKit has just attached.
    var isFocused = false

    func makeNSView(context: Context) -> TunerView {
        let view = TunerView()
        view.isHidden = true
        return view
    }

    func updateNSView(_ nsView: TunerView, context: Context) {
        nsView.caretColor = caretColor.map { NSColor($0) }
        nsView.applyTuning()
    }

    final class TunerView: NSView {
        private weak var tunedField: NSTextField?
        private var editingObserver: NSObjectProtocol?
        /// The shared field editor's caret before we tinted it, restored when
        /// a theme without a caret color takes over.
        private var systemCaretColor: NSColor?
        var caretColor: NSColor?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            tunedField = nil
            if let editingObserver {
                NotificationCenter.default.removeObserver(editingObserver)
                self.editingObserver = nil
            }
            applyTuning()
        }

        func applyTuning() {
            guard let field = resolvedField() else { return }
            field.focusRingType = .none
            field.isBordered = false
            field.isBezeled = false
            field.drawsBackground = false
            applyCaret(to: field)
            // Focus lands after this update; catch the editor once it's attached.
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field else { return }
                self.applyCaret(to: field)
            }
        }

        /// The caret lives on the window's shared field editor, which only
        /// exists while the field is editing, so apply it again each time
        /// editing begins.
        private func applyCaret(to field: NSTextField) {
            if let editor = field.currentEditor() as? NSTextView {
                if let caretColor {
                    if systemCaretColor == nil { systemCaretColor = editor.insertionPointColor }
                    editor.insertionPointColor = caretColor
                } else if let systemCaretColor {
                    editor.insertionPointColor = systemCaretColor
                }
            }
        }

        private func resolvedField() -> NSTextField? {
            if let tunedField, let window, tunedField.window === window {
                return tunedField
            }
            let field = Self.nearestTextField(from: self)
            tunedField = field
            if let editingObserver { NotificationCenter.default.removeObserver(editingObserver) }
            editingObserver = field.map { field in
                NotificationCenter.default.addObserver(
                    forName: NSControl.textDidBeginEditingNotification,
                    object: field,
                    queue: .main
                ) { [weak self, weak field] _ in
                    MainActor.assumeIsolated {
                        guard let self, let field else { return }
                        self.applyCaret(to: field)
                    }
                }
            }
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
