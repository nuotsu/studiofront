import AppKit
import SwiftUI
import ThemeKit

struct SettingsRootView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(AuthSession.self) private var auth

    static let windowWidth: CGFloat = 600
    static let minHeight: CGFloat = 360
    static let sidebarWidth: CGFloat = 200
    static let sidebarInset: CGFloat = 8
    static let sidebarCornerRadius: CGFloat = 16
    /// Extra inset from the window corner; AppKit's default is ~7pt.
    static let trafficLightLeading: CGFloat = 22
    static let trafficLightTop: CGFloat = 22
    /// Space below the window top so search sits under the inset traffic lights.
    static let trafficLightClearance: CGFloat = 44
    static let defaultHeight: CGFloat = 630

    @State private var query = ""
    @State private var selectedSearchID: String?
    @State private var searchFieldFocused = false
    @State private var search = SettingsSearchState()

    var body: some View {
        HStack(spacing: 0) {
            sidebarColumn
            detailColumn
        }
        // Draw under the transparent titlebar so the sidebar glass sits behind
        // the traffic lights. The HStack otherwise lays out in the titlebar
        // safe area and the lights float in the gap above the card.
        .ignoresSafeArea(.container, edges: .top)
        // The scene's "Settings" title would draw over the pane heading beneath
        // the transparent titlebar; SwiftUI keeps restoring it, so clear it here
        // rather than fighting it from AppKit.
        .navigationTitle("")
        .background(SettingsWindowChrome())
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
        .onAppear {
            AppDelegate.shared?.applyAppearance(settings.appearancePreference)
            AppDelegate.shared?.configureOpenSettingsWindow()
        }
    }

    private var sidebarColumn: some View {
        sidebarList
            .padding(.top, Self.trafficLightClearance)
            .padding(.leading, Self.sidebarInset)
            .padding(.bottom, Self.sidebarInset)
            .frame(maxHeight: .infinity)
            .background {
                GlassSurface(cornerRadius: Self.sidebarCornerRadius)
                    .padding(.leading, Self.sidebarInset)
                    .padding(.top, Self.sidebarInset)
                    .padding(.bottom, Self.sidebarInset)
            }
            .frame(width: Self.sidebarWidth)
    }

    private var detailColumn: some View {
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
        .padding(.top, 4)
        .padding(.bottom, 2)
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
            .scrollContentBackground(.hidden)
            .scrollEdgeEffectStyle(.soft, for: .top)
            .contentMargins(.top, -4, for: .scrollContent)
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

/// Transparent titlebar chrome so traffic lights sit over the floating sidebar glass.
struct SettingsWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> SettingsChromeView {
        let view = SettingsChromeView(frame: .zero)
        view.isHidden = true
        DispatchQueue.main.async { Self.configureWindowChrome(view.window) }
        return view
    }

    func updateNSView(_ nsView: SettingsChromeView, context: Context) {
        guard let window = nsView.window else { return }
        Self.applyWindowChrome(to: window)
    }

    /// AppKit finishes building the titlebar after the window appears, and SwiftUI
    /// restores the scene title later, so a single pass can run too early or be
    /// undone. Re-apply over the next few runloop turns.
    static func configureWindowChrome(_ window: NSWindow?) {
        guard let window else { return }
        applyWindowChrome(to: window)
        for delay in [0.05, 0.2, 0.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                applyWindowChrome(to: window)
            }
        }
    }

    static func applyWindowChrome(to window: NSWindow) {
        window.isRestorable = false
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
        insetTrafficLights(in: window)
    }

    /// AppKit pins the buttons to the window corner; shift them onto the sidebar
    /// glass. Re-applied after layout because `NSThemeFrame` resets frames.
    private static func insetTrafficLights(in window: NSWindow) {
        guard let close = window.standardWindowButton(.closeButton),
              let miniaturize = window.standardWindowButton(.miniaturizeButton),
              let zoom = window.standardWindowButton(.zoomButton),
              let container = close.superview,
              close.frame.width > 0
        else { return }

        container.clipsToBounds = false
        container.superview?.clipsToBounds = false

        let gap = miniaturize.frame.minX - close.frame.maxX
        let spacing = gap > 0 ? gap : 6
        let leading = SettingsRootView.trafficLightLeading
        let top = SettingsRootView.trafficLightTop
        let buttons = [close, miniaturize, zoom]
        var x = leading
        for button in buttons {
            let y: CGFloat = container.isFlipped
                ? top
                : container.bounds.height - top - button.frame.height
            let origin = NSPoint(x: x, y: y)
            if button.frame.origin != origin {
                button.setFrameOrigin(origin)
            }
            x += button.frame.width + spacing
        }
    }
}

final class SettingsChromeView: NSView {
    private var resizeObserver: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let resizeObserver {
            NotificationCenter.default.removeObserver(resizeObserver)
            self.resizeObserver = nil
        }
        SettingsWindowChrome.configureWindowChrome(window)
        guard let window else { return }
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            guard let window = self?.window else { return }
            SettingsWindowChrome.applyWindowChrome(to: window)
        }
    }

    override func layout() {
        super.layout()
        DispatchQueue.main.async { [weak self] in
            guard let window = self?.window else { return }
            SettingsWindowChrome.applyWindowChrome(to: window)
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
