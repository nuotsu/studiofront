import AppKit
import Carbon.HIToolbox

/// A system-wide hotkey, so Studiofront can be summoned while another app is
/// frontmost. Carbon's `RegisterEventHotKey` is the only API that delivers a key
/// combo to a background app without Accessibility permission — a global
/// `NSEvent` monitor would prompt for one and still not swallow the keystroke.
@MainActor
final class GlobalHotKeyMonitor {
    static let shared = GlobalHotKeyMonitor()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    private static let signature: OSType = 0x5346_4B59 // 'SFKY'

    private init() {}

    /// Re-registers the hotkey for the given combo. A combo with no modifiers is
    /// ignored: it would swallow that key in every app.
    func update(keyCode: UInt16, modifierFlags: NSEvent.ModifierFlags, action: @escaping () -> Void) {
        self.action = action
        installEventHandlerIfNeeded()
        unregister()

        let carbonModifiers = Self.carbonModifiers(modifierFlags)
        guard carbonModifiers != 0 else { return }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(keyCode),
            carbonModifiers,
            EventHotKeyID(signature: Self.signature, id: 1),
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        // Registration fails when another app already owns the combo; leaving it
        // unregistered is correct — the other app keeps it.
        if status == noErr {
            hotKeyRef = ref
        }
    }

    private func fire() {
        action?()
    }

    private func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, _ -> OSStatus in
                // Carbon calls back on the main thread, but it is a C context, so
                // hop explicitly rather than assuming isolation here.
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { GlobalHotKeyMonitor.shared.fire() }
                }
                return noErr
            },
            1,
            &spec,
            nil,
            &eventHandler
        )
    }

    private static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var carbon: UInt32 = 0
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        return carbon
    }
}
