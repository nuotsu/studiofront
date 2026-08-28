import SwiftUI
import LicenseKit

extension Notification.Name {
    static let dismissMenuBarWidget = Notification.Name("dismissMenuBarWidget")
}

@main
struct StudiofrontApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarWidgetRoot()
                .environment(appDelegate.store)
                .environment(appDelegate.settings)
                .environment(appDelegate.auth)
                .environment(appDelegate.license)
        } label: {
            MenuBarIconLabel(preference: appDelegate.settings.menuBarIconPreference)
                .contextMenu {
                    MenuBarExtraContextMenu()
                        .environment(appDelegate.license)
                }
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsRootView()
                .environment(appDelegate.settings)
                .environment(appDelegate.auth)
                .environment(appDelegate.license)
        }
        .windowToolbarStyle(.unified(showsTitle: false))
        .windowResizability(.contentSize)
        .defaultSize(width: SettingsRootView.windowWidth, height: SettingsRootView.defaultHeight)
        .defaultLaunchBehavior(.suppressed)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    AppDelegate.shared?.openSettingsWindow()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
