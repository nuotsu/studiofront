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
    private(set) lazy var presence = PresenceCoordinator(store: store, settings: settings)

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
        applyGlobalHotKey()
        store.onCurationChanged = { [weak self] in
            self?.sync.persistCuration()
        }
        store.onRefreshRequested = { [weak self] in
            guard let self else { return }
            self.sync.refresh(force: true)
        }
        store.onRowsReplaced = { [weak self] in
            self?.presence.refreshEligibleProjects()
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
            button.image = Self.menuBarStatusImage(named: settings.menuBarIconPreference.imageName)
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

    func applyMenuBarIcon(_ preference: MenuBarIconPreference) {
        statusItem?.button?.image = Self.menuBarStatusImage(named: preference.imageName)
    }

    /// Template glyph sized to menu-bar height, preserving the SVG aspect ratio.
    private static func menuBarStatusImage(named name: String) -> NSImage? {
        guard let source = NSImage(named: name) else { return nil }
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
        guard let item = statusItem, let button = item.button else { return }
        closePopover()

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: "Open Studiofront",
            action: #selector(openStudiofrontFromMenu(_:)),
            keyEquivalent: ""
        )
        if !settings.openStudiofrontCharacters.isEmpty {
            openItem.keyEquivalent = settings.openStudiofrontCharacters
            openItem.keyEquivalentModifierMask = settings.openStudiofrontModifierFlags
        }
        menu.addItem(openItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings", action: #selector(openSettingsFromMenu(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Appearance", action: #selector(openAppearanceFromMenu(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Keybindings", action: #selector(openKeybindingsFromMenu(_:)), keyEquivalent: "")
        menu.addItem(withTitle: "Account", action: #selector(openAccountFromMenu(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdatesFromMenu(_:)), keyEquivalent: "")
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        menu.addItem(withTitle: "Current version: v\(version)", action: nil, keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Studiofront", action: #selector(quitFromMenu(_:)), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }

        // Native status-item menu presentation (rather than manual `popUp`) avoids an
        // AppKit glitch where the menu renders truncated and resizes/relocates on hover.
        item.menu = menu
        button.performClick(nil)
        item.menu = nil
    }

    @objc private func openStudiofrontFromMenu(_ sender: Any?) {
        togglePopover()
    }

    @objc private func quitFromMenu(_ sender: Any?) {
        NSApp.terminate(sender)
    }

    @objc private func openSettingsFromMenu(_ sender: Any?) {
        openSettingsWindow(pane: .general)
    }

    @objc private func openAppearanceFromMenu(_ sender: Any?) {
        openSettingsWindow(pane: .appearance)
    }

    @objc private func openKeybindingsFromMenu(_ sender: Any?) {
        openSettingsWindow(pane: .keybindings)
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

    /// Summons the popover from the global hotkey. Unlike a status-item click,
    /// another app is frontmost here, so activate first or the popover appears
    /// without keyboard focus and its transient behavior closes it immediately.
    func togglePopoverFromGlobalHotKey() {
        if popover?.isShown == true {
            closePopover()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        togglePopover()
    }

    func applyGlobalHotKey() {
        GlobalHotKeyMonitor.shared.update(
            keyCode: UInt16(settings.openStudiofrontKeyCode),
            modifierFlags: settings.openStudiofrontModifierFlags
        ) { [weak self] in
            self?.togglePopoverFromGlobalHotKey()
        }
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

    func applyAppearance(_ preference: AppearancePreference) {
        // Appearance changes otherwise crossfade Liquid Glass materials/colors.
        // Force a zero-duration update across AppKit + tear down any in-flight
        // layer animations on the popover and Settings window.
        let appearance = preference.nsAppearance

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            defer { CATransaction.commit() }

            NSApp.appearance = appearance

            popover?.appearance = appearance
            if let view = popover?.contentViewController?.view {
                view.appearance = appearance
                Self.stripAnimations(from: view)
            }

            for window in NSApp.windows where Self.isSettingsWindow(window) {
                let previousBehavior = window.animationBehavior
                window.animationBehavior = .none
                window.appearance = appearance
                window.contentView?.appearance = appearance
                if let contentView = window.contentView {
                    Self.stripAnimations(from: contentView)
                }
                window.animationBehavior = previousBehavior
            }
        }
    }

    private static func stripAnimations(from view: NSView) {
        view.layer?.removeAllAnimations()
        for subview in view.subviews {
            stripAnimations(from: subview)
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
        presence.willShow()
    }

    func popoverDidClose(_ notification: Notification) {
        removeKeyMonitor()
        sync.cancel()
        presence.willHide()
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

        if matchesOpenStudioBinding(keyCode: keyCode, flags: flags) {
            openSelectedStudio()
            return true
        }
        if matchesFavoriteToggleBinding(keyCode: keyCode, flags: flags) {
            store.toggleFavoriteOnSelection()
            return true
        }
        if matchesGroupByCycleBinding(keyCode: keyCode, flags: flags) {
            store.cycleGroupBy()
            return true
        }

        if flags.contains(.command) {
            let character = characters.lowercased()
            switch character {
            case "c":
                store.copySelectedProjectID()
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
        case 53:
            if store.clearQueryOrSignalDismiss() {
                closePopover()
            }
            return true
        default:
            return false
        }
    }

    private func matchesOpenStudioBinding(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let pressed = AppSettings.normalizedOpenStudioKeyCode(keyCode)
        let bound = AppSettings.normalizedOpenStudioKeyCode(UInt16(settings.openStudioKeyCode))
        return pressed == bound && flags == settings.openStudioModifierFlags
    }

    private func matchesFavoriteToggleBinding(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == UInt16(settings.favoriteToggleKeyCode) && flags == settings.favoriteToggleModifierFlags
    }

    private func matchesGroupByCycleBinding(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == UInt16(settings.groupByCycleKeyCode) && flags == settings.groupByCycleModifierFlags
    }
}
