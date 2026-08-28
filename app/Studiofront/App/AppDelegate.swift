import AppKit
import SwiftUI
import StudioStore
import LicenseKit

extension Notification.Name {
    static let openSettingsRequested = Notification.Name("openSettingsRequested")
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate?

    let settings = AppSettings.load()
    let store = StudioStore()
    let auth = AuthSession()
    let license = LicenseService()
    private(set) lazy var sync = ProjectSyncService(store: store, auth: auth, settings: settings)
    private(set) lazy var presence = PresenceCoordinator(store: store, settings: settings)
    private(set) lazy var documentSearch = DocumentSearchCoordinator(store: store, settings: settings)

    /// Keeps the menu-bar widget window open for programmatic dismiss coordination.
    var isMenuBarPresented = false
    private var keyMonitor: Any?
    private var settingsWindowController: NSWindowController?
    private var isSettingsWindowOpen = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self

        applyActivationPolicy()
        NSApp.activate(ignoringOtherApps: true)

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
            Task { await self?.sync.handleAuthChange() }
        }
        license.onEntitlementChange = { [weak self] entitlement in
            self?.store.entitlement = StudioStoreEntitlement(
                isUnlimited: entitlement.isUnlimited,
                maxFavoriteProjects: entitlement.maxFavoriteProjects,
                maxFavoriteOrganizations: entitlement.maxFavoriteOrganizations
            )
        }
        Task {
            await auth.restoreOnLaunch()
            await self.sync.loadCache()
        }
        Task {
            await license.restoreOnLaunch()
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

    // MARK: - Menu bar widget

    func openMenuBarWidget() {
        applyAppearance(settings.appearancePreference)
        NSApp.activate(ignoringOtherApps: true)
        guard !isMenuBarPresented else { return }
        // MenuBarExtra has no presentation binding — toggle via its status item.
        performMenuBarExtraClick()
    }

    func closePopover() {
        guard isMenuBarPresented else { return }
        NotificationCenter.default.post(name: .dismissMenuBarWidget, object: nil)
    }

    func togglePopoverFromGlobalHotKey() {
        applyAppearance(settings.appearancePreference)
        // Activate first so the MenuBarExtra window can take key focus when
        // another app was frontmost (same requirement as the old NSPopover path).
        NSApp.activate(ignoringOtherApps: true)
        if isMenuBarPresented {
            closePopover()
        } else {
            performMenuBarExtraClick()
        }
    }

    /// `MenuBarExtra` owns the status item; SwiftUI does not expose show/hide.
    /// Clicking its button is the supported AppKit toggle for `.window` style.
    private func performMenuBarExtraClick() {
        guard let button = menuBarExtraStatusItem()?.button else { return }
        button.performClick(nil)
    }

    private func menuBarExtraStatusItem() -> NSStatusItem? {
        for window in NSApp.windows {
            if let statusItem = window.value(forKey: "statusItem") as? NSStatusItem {
                return statusItem
            }
        }
        return nil
    }

    func menuBarWidgetDidAppear() {
        isMenuBarPresented = true
        store.prepareForOpen()
        applyAppearance(settings.appearancePreference)
        installKeyMonitor()
        presence.willShow()
        documentSearch.willShow()
        sync.refreshIfStale(interval: settings.refreshInterval)
        license.refreshIfStale()
    }

    func menuBarWidgetDidDisappear() {
        isMenuBarPresented = false
        removeKeyMonitor()
        presence.willHide()
        documentSearch.willHide()
        DispatchQueue.main.async { [weak self] in
            self?.applyActivationPolicy()
        }
    }

    func applyMenuBarIcon(_ preference: MenuBarIconPreference) {
        _ = preference
    }

    func checkForUpdates() {
        AppUpdater.shared.checkForUpdates(nil)
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

    /// Opens a Studio or document deep link only when the project is unlocked.
    /// Locked projects route to Settings → License instead.
    func openUnlockedURL(_ url: URL, projectID: String, dismiss: Bool = true) {
        guard !store.isProjectLocked(projectID) else {
            openSettingsWindow(pane: .license)
            return
        }
        openURL(url, dismiss: dismiss)
    }

    func openSelectedStudio() {
        guard let row = store.selectedRow else { return }
        guard let url = row.resolvedStudioURL(preferExternal: settings.studioURLPreference == .external) else { return }
        openUnlockedURL(url, projectID: row.id)
    }

    func applyAppearance(_ preference: AppearancePreference) {
        // Appearance changes otherwise crossfade Liquid Glass materials/colors.
        // Force a zero-duration update across AppKit + tear down any in-flight
        // layer animations on the popover and Settings window.
        let appearance = Self.resolvedNSAppearance(for: preference)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0
            context.allowsImplicitAnimation = false
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            CATransaction.setAnimationDuration(0)
            defer { CATransaction.commit() }

            NSApp.appearance = appearance

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

    private static func resolvedNSAppearance(for preference: AppearancePreference) -> NSAppearance {
        if let appearance = preference.nsAppearance {
            return appearance
        }
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSAppearance(named: isDark ? .darkAqua : .aqua) ?? NSApp.effectiveAppearance
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

        if isSettingsWindowOpen {
            orderSettingsFront()
            return
        }

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
        isSettingsWindowOpen = true
        window.delegate = self
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
        SettingsSplitViewTuner.removeSidebarToggleItems(from: window)
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
                .environment(license)
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
        isSettingsWindowOpen = true
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, Self.isSettingsWindow(window) {
            isSettingsWindowOpen = false
            if settingsWindowController?.window === window {
                settingsWindowController = nil
            }
        }
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

    // MARK: - Keyboard

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, Thread.isMainThread else { return event }
            if event.type == .flagsChanged {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                MainActor.assumeIsolated {
                    self.store.updateCommandKeyHeld(flags.contains(.command))
                }
                return event
            }
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
        store.updateCommandKeyHeld(false)
    }

    private func handlePopoverKey(keyCode: UInt16, modifierRaw: UInt, characters: String) -> Bool {
        guard isMenuBarPresented else { return false }
        let flags = NSEvent.ModifierFlags(rawValue: modifierRaw).intersection(.deviceIndependentFlagsMask)

        if matchesOpenStudioBinding(keyCode: keyCode, flags: flags) {
            openSelectedStudio()
            return true
        }
        if matchesOpenDocumentBinding(keyCode: keyCode, flags: flags) {
            openSelectedDocument()
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
                // Favorites jump is disabled while a search query is active —
                // results aren't favorited-first and the legends are hidden.
                guard store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    return true
                }
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
        let pressed = AppSettings.normalizedEnterKeyCode(keyCode)
        let bound = AppSettings.normalizedEnterKeyCode(UInt16(settings.openStudioKeyCode))
        return pressed == bound && flags == settings.openStudioModifierFlags
    }

    private func matchesOpenDocumentBinding(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        let pressed = AppSettings.normalizedEnterKeyCode(keyCode)
        let bound = AppSettings.normalizedEnterKeyCode(UInt16(settings.openDocumentKeyCode))
        return pressed == bound && flags == settings.openDocumentModifierFlags
    }

    private func matchesFavoriteToggleBinding(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == UInt16(settings.favoriteToggleKeyCode) && flags == settings.favoriteToggleModifierFlags
    }

    private func matchesGroupByCycleBinding(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        keyCode == UInt16(settings.groupByCycleKeyCode) && flags == settings.groupByCycleModifierFlags
    }

    /// Opens the selected list item's document — a dedicated document search
    /// row's match, or the project row's last-edited caption fallback.
    private func openSelectedDocument() {
        guard let item = store.selectedListItem else { return }
        switch item {
        case let .document(project, document):
            guard let url = document.deepLinkURL else { return }
            openUnlockedURL(url, projectID: project.id)
        case let .project(row):
            guard let url = store.documentDisplay(for: row)?.deepLinkURL else { return }
            openUnlockedURL(url, projectID: row.id)
        }
    }
}
