import AppKit
import SwiftUI

struct SettingsRootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthSession.self) private var auth

    static let windowWidth: CGFloat = 600
    static let minHeight: CGFloat = 360
    static let sidebarWidth: CGFloat = 200
    static let defaultHeight: CGFloat = 420

    @State private var query = ""
    @State private var selectedSearchID: String?
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
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .onChange(of: query) { _, _ in
            selectedSearchID = nil
        }
    }

    @ViewBuilder
    private var sidebarList: some View {
        @Bindable var auth = auth
        let matches = SettingsSearchIndex.matches(query)
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            List(selection: $auth.selectedSettingsPane) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(pane)
                }
            }
            .sidebarSearchChrome(searchField: searchField)
        } else if matches.isEmpty {
            List {
                Text("No Results")
                    .foregroundStyle(.secondary)
            }
            .sidebarSearchChrome(searchField: searchField)
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
            .sidebarSearchChrome(searchField: searchField)
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

private extension View {
    func sidebarSearchChrome(searchField: some View) -> some View {
        listStyle(.sidebar)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .safeAreaBar(edge: .top) {
                searchField
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

    private static func configureWindowChrome(_ window: NSWindow?) {
        guard let window else { return }
        window.styleMask.insert(.fullSizeContentView)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.toolbarStyle = .unified
        hideSidebarToggle(in: window)
    }

    /// SwiftUI's `.toolbar(removing: .sidebarToggle)` doesn't reliably remove
    /// AppKit's automatic sidebar toggle button from this forced NSToolbar, so
    /// strip it directly whenever the toolbar is (re)built.
    private static func hideSidebarToggle(in window: NSWindow) {
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
