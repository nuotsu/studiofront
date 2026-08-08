import Foundation
import Sparkle

/// Owns the Sparkle updater for OTA updates from the GitHub Releases appcast.
@MainActor
final class AppUpdater {
    static let shared = AppUpdater()

    private let controller: SPUStandardUpdaterController

    private init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates(_ sender: Any? = nil) {
        controller.checkForUpdates(sender)
    }
}
