import AppKit
import SwiftUI
import ThemeKit
import StudioStore

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?

    private static let statusItemAutosaveName = "dev.nuotsu.Studiofront.statusItem"
    private static let statusItemPreferredPosition: Double = 48

    let settings = AppSettings.load()
    let store = StudioStore()
    let auth = AuthSession()
    private(set) lazy var sync = ProjectSyncService(store: store, auth: auth)

    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var keyMonitor: Any?
    private var settingsWindowController: NSWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        applyActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        clearStaleStatusItemVisibility()
        ensureStatusItem()

        let pop = NSPopover()
        pop.behavior = .transient
        pop.animates = true
        pop.contentSize = NSSize(width: 516, height: 640)
        pop.delegate = self
        let hosting = NSHostingController(rootView: popoverRoot)
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        pop.contentViewController = hosting
        popover = pop

        applyAppearance(settings.appearancePreference)
        applyActivationPolicy()
        store.onCurationChanged = { [weak self] in
            self?.sync.persistCuration()
        }
        store.onRefreshRequested = { [weak self] in
            guard let self else { return }
            self.sync.refresh(force: true)
        }
        auth.onStatusChange = { [weak self] in
            self?.sync.handleAuthChange()
        }
        Task {
            await auth.restoreOnLaunch()
            self.sync.loadCache()
        }
        // Start Sparkle after launch so the first-run permission prompt is not buried.
        _ = AppUpdater.shared
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            openSettingsWindow()
        }
        return true
    }

    // MARK: - Status item

    private func clearStaleStatusItemVisibility() {
        let defaults = UserDefaults.standard
        let keys = [
            "NSStatusItem Visible \(Self.statusItemAutosaveName)",
            "NSStatusItem Preferred Position \(Self.statusItemAutosaveName)",
            "NSStatusItem Visible Item-0",
            "NSStatusItem Preferred Position Item-0",
        ]
        for key in keys {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: "NSStatusItem Visible \(Self.statusItemAutosaveName)")
    }

    private func ensureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.autosaveName = Self.statusItemAutosaveName
        item.isVisible = true
        if let button = item.button {
            button.image = Self.menuBarStatusImage()
            button.imagePosition = .imageOnly
            button.toolTip = "Studiofront"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        UserDefaults.standard.set(true, forKey: "NSStatusItem Visible \(Self.statusItemAutosaveName)")
        if UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(Self.statusItemAutosaveName)") == nil {
            UserDefaults.standard.set(
                Self.statusItemPreferredPosition,
                forKey: "NSStatusItem Preferred Position \(Self.statusItemAutosaveName)"
            )
        }
    }

    /// Template glyph sized to menu-bar height, preserving the SVG aspect ratio.
    private static func menuBarStatusImage() -> NSImage? {
        guard let source = NSImage(named: "MenuBarIcon") else { return nil }
        let height: CGFloat = 16
        let aspect = source.size.width / max(source.size.height, 1)
        let size = NSSize(width: (height * aspect).rounded(), height: height)
        let image = NSImage(size: size)
        image.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )
        image.unlockFocus()
        image.isTemplate = true
        image.accessibilityDescription = "Studiofront"
        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            showStatusItemMenu()
        } else {
            togglePopover()
        }
    }

    private func showStatusItemMenu() {
        guard let button = statusItem?.button else { return }
        closePopover()

        let menu = NSMenu()
        menu.addItem(withTitle: "Settings", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Account", action: #selector(openAccountFromMenu(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesFromMenu(_:)), keyEquivalent: "")
        for item in menu.items {
            item.target = self
        }

        let point = NSPoint(x: 0, y: button.bounds.height + 2)
        menu.popUp(positioning: nil, at: point, in: button)
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        openSettingsWindow(pane: .general)
    }

    @objc private func openAccountFromMenu(_ sender: Any?) {
        openSettingsWindow(pane: .account)
    }

    @objc private func checkForUpdatesFromMenu(_ sender: Any?) {
        AppUpdater.shared.checkForUpdates(sender)
    }

    func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.prepareForOpen()
            applyAppearance(settings.appearancePreference)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            sync.refreshIfStale(interval: settings.refreshInterval)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }

    func openURL(_ url: URL, dismiss: Bool = true) {
        NSWorkspace.shared.open(url)
        if dismiss {
            closePopover()
        }
    }

    func openSelectedStudio() {
        guard let url = store.selectedRow?.resolvedStudioURL else { return }
        openURL(url)
    }

    func openSelectedSite() {
        guard let url = store.selectedRow?.curation.primaryFrontendURL else { return }
        openURL(url)
    }

    func applyAppearance(_ preference: AppearancePreference) {
        popover?.appearance = preference.nsAppearance
        popover?.contentViewController?.view.appearance = preference.nsAppearance
        if let window = NSApp.windows.first(where: Self.isSettingsWindow) {
            window.appearance = preference.nsAppearance
        }
    }

    /// `showInDock` is the only input: an accessory app can still own and focus
    /// the Settings window, so keeping the icon for an open window would just
    /// contradict the setting.
    func applyActivationPolicy() {
        NSApp.setActivationPolicy(settings.showInDock ? .regular : .accessory)
    }

    func openSettingsWindow(pane: SettingsPane = .general) {
        auth.selectedSettingsPane = pane
        applyActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)
        // Post while the popover is still mounted so SwiftUI `openWindow` can run.
        NotificationCenter.default.post(name: .openSettingsRequested, object: nil)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.closePopover()
            self.orderSettingsFront()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.ensureSettingsWindow()
        }
    }

    func configureOpenSettingsWindow() {
        guard let window = NSApp.windows.first(where: Self.isSettingsWindow) else { return }
        configureSettingsWindowChrome(window)
    }

    private func configureSettingsWindowChrome(_ window: NSWindow) {
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.styleMask.insert([.fullSizeContentView, .resizable])
        window.toolbarStyle = .unified
        window.minSize = NSSize(width: SettingsRootView.windowWidth, height: SettingsRootView.minHeight)
        window.maxSize = NSSize(width: SettingsRootView.windowWidth, height: 10_000)
        window.contentMinSize = NSSize(width: SettingsRootView.windowWidth, height: SettingsRootView.minHeight)
        window.contentMaxSize = NSSize(width: SettingsRootView.windowWidth, height: 10_000)
        window.appearance = settings.appearancePreference.nsAppearance
    }

    private func orderSettingsFront() {
        guard let window = NSApp.windows.first(where: Self.isSettingsWindow) else { return }
        configureSettingsWindowChrome(window)
        window.makeKeyAndOrderFront(nil)
        window.collectionBehavior.insert(.moveToActiveSpace)
        // Accessory apps are not activated for free the way a dock-visible app
        // is, and the window only exists by this point, so re-activate here or
        // Settings can surface unfocused behind whatever was frontmost.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Accessory apps often never materialize a SwiftUI `Window` / `Settings` scene
    /// from `showSettingsWindow:`. Host Settings ourselves if nothing appeared.
    private func ensureSettingsWindow() {
        if NSApp.windows.contains(where: { $0.isVisible && Self.isSettingsWindow($0) }) {
            orderSettingsFront()
            return
        }
        presentAppKitSettingsWindow()
    }

    private func presentAppKitSettingsWindow() {
        if let window = settingsWindowController?.window {
            window.appearance = settings.appearancePreference.nsAppearance
            window.makeKeyAndOrderFront(nil)
            return
        }

        let hosting = NSHostingController(
            rootView: SettingsRootView()
                .environment(settings)
                .environment(auth)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.isReleasedWhenClosed = false
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.setContentSize(NSSize(width: SettingsRootView.windowWidth, height: SettingsRootView.defaultHeight))
        configureSettingsWindowChrome(window)
        window.center()
        window.delegate = self
        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            self?.applyActivationPolicy()
        }
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let id = window.identifier?.rawValue ?? ""
        if id == "settings" || id.lowercased().contains("settings") { return true }
        return window.title.localizedCaseInsensitiveContains("settings")
            || window.title.localizedCaseInsensitiveContains("general")
            || window.title.localizedCaseInsensitiveContains("account")
    }

    // MARK: - Popover root

    private var popoverRoot: some View {
        PopoverRootView()
            .environment(store)
            .environment(settings)
            .environment(auth)
    }

    // MARK: - Keyboard

    func popoverWillShow(_ notification: Notification) {
        installKeyMonitor()
    }

    func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
        sync.cancel()
        DispatchQueue.main.async { [weak self] in
            self?.applyActivationPolicy()
        }
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, Thread.isMainThread else { return event }
            let keyCode = event.keyCode
            let modifierRaw = event.modifierFlags.rawValue
            let characters = event.charactersIgnoringModifiers ?? ""
            let consumed = MainActor.assumeIsolated {
                self.handlePopoverKey(keyCode: keyCode, modifierRaw: modifierRaw, characters: characters)
            }
            return consumed ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func handlePopoverKey(keyCode: UInt16, modifierRaw: UInt, characters: String) -> Bool {
        guard popover?.isShown == true else { return false }
        let flags = NSEvent.ModifierFlags(rawValue: modifierRaw).intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let option = flags.contains(.option)

        if command {
            let character = characters.lowercased()
            switch character {
            case "c":
                store.copySelectedProjectID()
                return true
            case "f":
                store.toggleFavoriteOnSelection()
                return true
            case "r":
                store.refresh()
                return true
            case ",":
                openSettingsWindow()
                return true
            case "k":
                store.searchFocusToken &+= 1
                return true
            case "1", "2", "3", "4", "5", "6", "7", "8", "9":
                if let index = Int(character) {
                    store.jumpToFavorite(index)
                }
                return true
            default:
                return false
            }
        }

        switch keyCode {
        case 126:
            store.selectPrevious()
            return true
        case 125:
            store.selectNext()
            return true
        case 36, 76:
            if option {
                openSelectedSite()
            } else {
                openSelectedStudio()
            }
            return true
        case 53:
            if store.clearQueryOrSignalDismiss() {
                closePopover()
            }
            return true
        default:
            return false
        }
    }
}
