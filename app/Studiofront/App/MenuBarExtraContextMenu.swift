import SwiftUI
import LicenseKit

/// Right-click / control-click menu for the menu-bar icon (replaces the old
/// `NSStatusItem` context menu).
struct MenuBarExtraContextMenu: View {
    @Environment(LicenseService.self) private var license

    var body: some View {
        Button("Open Studiofront") {
            AppDelegate.shared?.openMenuBarWidget()
        }
        Divider()
        Button("Settings") {
            AppDelegate.shared?.openSettingsWindow(pane: .general)
        }
        Button("Appearance") {
            AppDelegate.shared?.openSettingsWindow(pane: .appearance)
        }
        Button("Keybindings") {
            AppDelegate.shared?.openSettingsWindow(pane: .keybindings)
        }
        Button("Account") {
            AppDelegate.shared?.openSettingsWindow(pane: .account)
        }
        Divider()
        Button("License") {
            AppDelegate.shared?.openSettingsWindow(pane: .license)
        }
        licenseStatusItem
        Divider()
        Button("Check for Updates…") {
            AppDelegate.shared?.checkForUpdates()
        }
        Text("Current version: v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")")
        Divider()
        Button("Quit Studiofront") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    @ViewBuilder
    private var licenseStatusItem: some View {
        switch license.status {
        case let .trial(daysLeft):
            Text(daysLeft == 1 ? "1 day left" : "\(daysLeft) days left")
        case .free, .expired:
            Button("Upgrade") {
                AppDelegate.shared?.openSettingsWindow(pane: .license)
            }
        case .validating, .licensed:
            EmptyView()
        }
    }
}
