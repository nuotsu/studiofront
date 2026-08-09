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
    @FocusState private var searchFieldFocused: Bool
    @State private var search = SettingsSearchState()

    var body: some View {
        @Bindable var auth = auth
        NavigationSplitView(columnVisibility: .constant(.all)) {
            sidebarList
                .navigationSplitViewColumnWidth(
                    min: Self.sidebarWidth,
                    ideal: Self.sidebarWidth,
                    max: Self.sidebarWidth
                )
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
        .toolbar(removing: .sidebarToggle)
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
        .onAppear {
            AppDelegate.shared?.applyAppearance(settings.appearancePreference)
            AppDelegate.shared?.configureOpenSettingsWindow()
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .focused($searchFieldFocused)
                .onSubmit { selectFirstMatch() }
            if !query.isEmpty {
                Button {
                    query = ""
                    selectedSearchID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
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
            // Switching the sidebar between browse and results mode rebuilds this
            // field, so re-assert focus once that settles or typing drops it.
            DispatchQueue.main.async { searchFieldFocused = true }
        }
    }

    private var sidebarList: some View {
        sidebarContent
            .listStyle(.sidebar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            // Attached once, outside the branches below: hanging it off each list
            // rebuilt the text field on the first keystroke, which dropped focus.
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

/// Pins the Tahoe floating sidebar to a fixed leading column and stretches it
/// full-height under the titlebar so traffic lights sit inside the glass.
private struct SettingsSplitViewTuner: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async { Self.tune(from: view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { Self.tune(from: nsView) }
    }

    private static func tune(from view: NSView) {
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
        split.view.needsLayout = true
        split.view.layoutSubtreeIfNeeded()
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
    }

    /// SwiftUI's `.toolbar(removing: .sidebarToggle)` doesn't reliably remove
    /// AppKit's automatic sidebar toggle button from this forced NSToolbar, so
    /// strip it directly whenever the toolbar is (re)built.
    private static func removeSidebarToggleItems(from window: NSWindow) {
        guard let toolbar = window.toolbar else { return }
        while let index = toolbar.items.firstIndex(where: { $0.itemIdentifier == .toggleSidebar }) {
            toolbar.removeItem(at: index)
        }
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
