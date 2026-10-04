import AppKit
import SwiftUI

struct SettingsRootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthSession.self) private var auth

    static let windowWidth: CGFloat = 600
    static let minHeight: CGFloat = 360
    static let sidebarWidth: CGFloat = 200
    static let defaultHeight: CGFloat = 630

    @State private var query = ""
    @State private var selectedSearchID: String?
    @State private var searchFieldFocused = false
    @State private var search = SettingsSearchState()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var auth = auth
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebarList
                .navigationSplitViewColumnWidth(
                    min: Self.sidebarWidth,
                    ideal: Self.sidebarWidth,
                    max: Self.sidebarWidth
                )
                // Official SwiftUI hook; on Tahoe the control is often chrome,
                // not a toolbar item, so the AppKit tuner also hides it.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            Group {
                switch auth.selectedSettingsPane {
                case .general:
                    GeneralSettingsView()
                case .appearance:
                    AppearanceSettingsView()
                case .account:
                    AccountSettingsView()
                case .keybindings:
                    KeybindingsSettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea(.container, edges: .top)
        }
        .navigationSplitViewStyle(.automatic)
        // The scene's "Settings" title would draw over the pane heading beneath
        // the transparent titlebar; SwiftUI keeps restoring it, so clear it here
        // rather than fighting it from AppKit.
        .navigationTitle("")
        // Force an NSToolbar so the sidebar can own a titlebar section (traffic lights).
        .toolbar {
            ToolbarSpacer(.flexible)
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .background(SettingsSplitViewTuner())
        .environment(search)
        .frame(
            minWidth: Self.windowWidth,
            idealWidth: Self.windowWidth,
            maxWidth: Self.windowWidth,
            minHeight: Self.minHeight,
            maxHeight: .infinity
        )
        .preferredColorScheme(settings.appearancePreference.colorScheme)
        .transaction { $0.disablesAnimations = true }
        .animation(nil, value: settings.appearancePreference)
        .id(settings.appearancePreference)
        .onChange(of: columnVisibility) { _, visibility in
            if visibility != .all {
                columnVisibility = .all
            }
        }
        .onAppear {
            AppDelegate.shared?.applyAppearance(settings.appearancePreference)
            AppDelegate.shared?.configureOpenSettingsWindow()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            // AppKit-backed field: SwiftUI `TextField` + `.focused` select-alls on
            // every first-responder pass, and the first keystroke both swaps the
            // sidebar `List` type and inserts the clear button — either of which
            // can recreate the field mid-typing. This control keeps the caret at
            // the end across those rebuilds instead of selecting the query.
            SettingsSidebarSearchField(
                text: $query,
                isFocused: $searchFieldFocused,
                onSubmit: selectFirstMatch
            )
            .frame(maxWidth: .infinity)
            // Keep the clear control mounted so the first character doesn't
            // change this HStack's child count and recreate the text field.
            Button {
                query = ""
                selectedSearchID = nil
                searchFieldFocused = true
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear search")
            .opacity(query.isEmpty ? 0 : 1)
            .disabled(query.isEmpty)
            .allowsHitTesting(!query.isEmpty)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    // Faint dark wash so the field reads as recessed into the
                    // sidebar glass rather than as a bordered control.
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.06))
                }
        }
        // 10 matches the sidebar rows' own inset, so the field lines up with them.
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onChange(of: query) { _, _ in
            selectedSearchID = nil
            // Switching the sidebar between browse and results mode can still
            // tear down this safe-area bar; reassert focus after that settles.
            DispatchQueue.main.async {
                searchFieldFocused = true
            }
        }
    }

    private var sidebarList: some View {
        // `sidebarContent` is one of three differently-typed `List`s depending on
        // query state. Even attaching `.safeAreaBar` "outside" that branch (rather
        // than inside each arm) doesn't stop the rebuild: modifiers are generic
        // over their base view's concrete type, so when that type changes here
        // (e.g. on the query's empty <-> non-empty transition), the whole modified
        // subtree — including the search field inside the bar — is torn down and
        // recreated too, dropping its focus. Erasing the type with `AnyView` first
        // keeps the base type stable across branches, so the bar (and the search
        // field inside it) survives.
        AnyView(sidebarContent)
            .listStyle(.sidebar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) {
                searchField
            }
    }

    @ViewBuilder
    private var sidebarContent: some View {
        @Bindable var auth = auth
        let matches = SettingsSearchIndex.matches(query)
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            List(selection: $auth.selectedSettingsPane) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(pane)
                }
            }
        } else if matches.isEmpty {
            List {
                Text("No Results")
                    .foregroundStyle(.secondary)
            }
        } else {
            List(selection: $selectedSearchID) {
                ForEach(matches) { item in
                    Label {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                            Text(item.pane.title)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: item.systemImage)
                    }
                    .tag(Optional.some(item.id))
                }
            }
            .onChange(of: selectedSearchID) { _, id in
                guard let id, let item = matches.first(where: { $0.id == id }) else { return }
                jump(to: item)
            }
        }
    }

    private func selectFirstMatch() {
        let matches = SettingsSearchIndex.matches(query)
        guard let first = matches.first else { return }
        selectedSearchID = first.id
        jump(to: first)
    }

    private func jump(to item: SettingsSearchItem) {
        auth.selectedSettingsPane = item.pane
        search.highlight(resolvedTarget(item.target))
    }

    private func resolvedTarget(_ target: SettingsSearchTarget) -> SettingsSearchTarget {
        switch target {
        case .cliLogin, .personalToken:
            auth.isSignedIn ? .accountIdentity : target
        case .signOut:
            auth.isSignedIn ? .signOut : .accountIdentity
        default:
            target
        }
    }
}

/// Pins the Tahoe floating sidebar to a fixed leading column, stretches it
/// full-height under the titlebar so traffic lights sit inside the glass, and
/// keeps the sidebar from collapsing (including hiding the chrome toggle).
struct SettingsSplitViewTuner: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsSplitViewTunerView {
        let view = SettingsSplitViewTunerView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async { Self.tune(from: view, relayout: true) }
        return view
    }

    func updateNSView(_ nsView: SettingsSplitViewTunerView, context: Context) {
        DispatchQueue.main.async { Self.tune(from: nsView, relayout: true) }
    }

    fileprivate static func tune(from view: NSView, relayout: Bool) {
        guard let split = enclosingSplitViewController(from: view) else { return }
        configureWindowChrome(split.view.window)

        for item in split.splitViewItems {
            switch item.behavior {
            case .sidebar:
                item.minimumThickness = SettingsRootView.sidebarWidth
                item.maximumThickness = SettingsRootView.sidebarWidth
                item.preferredThicknessFraction = NSSplitViewItem.unspecifiedDimension
                item.holdingPriority = .defaultHigh
                item.canCollapse = false
                item.canCollapseFromWindowResize = false
                item.allowsFullHeightLayout = true
                item.titlebarSeparatorStyle = .none
            default:
                item.holdingPriority = .defaultLow
                item.automaticallyAdjustsSafeAreaInsets = true
                item.titlebarSeparatorStyle = .none
            }
        }
        split.minimumThicknessForInlineSidebars = 0
        if relayout {
            split.view.needsLayout = true
            split.view.layoutSubtreeIfNeeded()
        }
        if split.splitView.subviews.count > 1 {
            split.splitView.setPosition(SettingsRootView.sidebarWidth, ofDividerAt: 0)
        }
    }

    /// AppKit finishes building the titlebar and toolbar after the split view
    /// appears, and rebuilds them later, so a single pass can run too early or be
    /// undone. Re-apply over the next few runloop turns.
    private static func configureWindowChrome(_ window: NSWindow?) {
        guard let window else { return }
        applyWindowChrome(to: window)
        for delay in [0.05, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                applyWindowChrome(to: window)
            }
        }
    }

    private static func applyWindowChrome(to window: NSWindow) {
        window.styleMask.insert(.fullSizeContentView)
        // `fullSizeContentView` draws the titlebar over the content, so a visible
        // window title lands on top of the pane's own heading. `titleVisibility`
        // alone doesn't stick here — SwiftUI keeps restoring the scene title — so
        // clear the string too. The window is matched by its "settings"
        // identifier, not its title, so nothing depends on the text.
        window.titleVisibility = .hidden
        window.title = ""
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        removeSidebarToggleItems(from: window)
        hideSidebarToggleChrome(in: window)
    }

    /// Toolbar-item sweep for the (currently theoretical) case where the toggle
    /// is a real `NSToolbarItem`. On macOS 26 it is usually titlebar chrome.
    static func removeSidebarToggleItems(from window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        while let index = toolbar.items.firstIndex(where: {
            $0.itemIdentifier == .toggleSidebar
                || $0.itemIdentifier.rawValue.localizedCaseInsensitiveContains("togglesidebar")
        }) {
            toolbar.removeItem(at: index)
        }
    }

    /// The Tahoe floating-sidebar collapse control sits in the titlebar next to
    /// the traffic lights and is not an `NSToolbarItem`. Hide any control whose
    /// action or identity is the sidebar toggle, without touching traffic lights.
    private static func hideSidebarToggleChrome(in window: NSWindow) {
        let trafficLights: Set<ObjectIdentifier> = Set(
            [
                window.standardWindowButton(.closeButton),
                window.standardWindowButton(.miniaturizeButton),
                window.standardWindowButton(.zoomButton),
            ]
            .compactMap { $0 }
            .map { ObjectIdentifier($0) }
        )
        if let frame = window.contentView?.superview {
            hideSidebarToggleViews(in: frame, skipping: trafficLights)
        }
        if let content = window.contentView {
            hideSidebarToggleViews(in: content, skipping: trafficLights)
        }
    }

    private static func hideSidebarToggleViews(in root: NSView, skipping trafficLights: Set<ObjectIdentifier>) {
        if isSidebarToggle(root, skipping: trafficLights), !root.isHidden {
            root.isHidden = true
        }
        for subview in root.subviews {
            hideSidebarToggleViews(in: subview, skipping: trafficLights)
        }
    }

    private static func isSidebarToggle(_ view: NSView, skipping trafficLights: Set<ObjectIdentifier>) -> Bool {
        if trafficLights.contains(ObjectIdentifier(view)) { return false }

        let className = String(describing: type(of: view))
        let identifier = view.identifier?.rawValue ?? ""
        if className.localizedCaseInsensitiveContains("togglesidebar")
            || identifier.localizedCaseInsensitiveContains("togglesidebar")
        {
            return true
        }

        guard let control = view as? NSControl else { return false }
        let actionName = control.action.map { NSStringFromSelector($0) } ?? ""
        if actionName.localizedCaseInsensitiveContains("toggleSidebar") {
            return true
        }

        let label = [
            control.toolTip,
            (control as? NSButton)?.title,
            control.accessibilityLabel(),
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .localizedLowercase
        return label.contains("sidebar") && (label.contains("hide") || label.contains("show") || label.contains("toggle"))
    }

    private static func enclosingSplitViewController(from view: NSView) -> NSSplitViewController? {
        var current: NSView? = view
        while let candidate = current {
            if let split = candidate.nextResponder as? NSSplitViewController {
                return split
            }
            if let splitView = candidate as? NSSplitView,
               let split = splitView.delegate as? NSSplitViewController {
                return split
            }
            current = candidate.superview
        }
        return nil
    }
}

final class SettingsSplitViewTunerView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        SettingsSplitViewTuner.tune(from: self, relayout: true)
    }

    override func layout() {
        super.layout()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            // Re-hide chrome without requesting another split-view layout pass.
            SettingsSplitViewTuner.tune(from: self, relayout: false)
        }
    }
}

/// Settings sidebar search field that keeps an insertion-point caret when
/// AppKit would otherwise select-all on `becomeFirstResponder()` — which
/// happens whenever SwiftUI rebuilds the surrounding sidebar mid-typing.
private struct SettingsSidebarSearchField: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CaretPreservingTextField {
        let field = CaretPreservingTextField()
        field.placeholderString = "Search"
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        return field
    }

    func updateNSView(_ field: CaretPreservingTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
            field.moveCaretToEnd()
        }
        let editorIsFirst = field.currentEditor() != nil
            && field.window?.firstResponder === field.currentEditor()
        if isFocused, !editorIsFirst {
            DispatchQueue.main.async {
                field.window?.makeFirstResponder(field)
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SettingsSidebarSearchField

        init(parent: SettingsSidebarSearchField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
        }

        @objc func submit(_ sender: NSTextField) {
            parent.onSubmit()
        }
    }
}

private final class CaretPreservingTextField: NSTextField {
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        moveCaretToEnd()
        // AppKit may finalize select-all after this returns; collapse again.
        DispatchQueue.main.async { [weak self] in
            self?.moveCaretToEnd()
        }
        return ok
    }

    func moveCaretToEnd() {
        guard let editor = currentEditor() else { return }
        let end = (stringValue as NSString).length
        editor.selectedRange = NSRange(location: end, length: 0)
    }
}
