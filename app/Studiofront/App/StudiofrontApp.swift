import SwiftUI

@main
struct StudiofrontApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Settings", id: "settings") {
            SettingsRootView()
                .environment(appDelegate.settings)
                .environment(appDelegate.auth)
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
