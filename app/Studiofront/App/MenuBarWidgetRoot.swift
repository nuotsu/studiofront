import SwiftUI

/// Hosts the widget and wires AppDelegate lifecycle hooks when the
/// `MenuBarExtra` window appears and disappears.
struct MenuBarWidgetRoot: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        PopoverRootView()
            .onAppear {
                AppDelegate.shared?.menuBarWidgetDidAppear()
            }
            .onDisappear {
                AppDelegate.shared?.menuBarWidgetDidDisappear()
            }
            .onReceive(NotificationCenter.default.publisher(for: .dismissMenuBarWidget)) { _ in
                dismiss()
            }
    }
}
