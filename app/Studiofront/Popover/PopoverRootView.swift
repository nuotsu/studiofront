import SwiftUI
import ThemeKit
import StudioStore

struct PopoverRootView: View {
    @Environment(StudioStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AuthSession.self) private var auth
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searchFocused: Bool
    @State private var avatarTooltip: AvatarTooltipDisplay?
    @State private var avatarTooltipSize: CGSize = .zero
    @State private var headerMinYs: [String: CGFloat] = [:]

    var body: some View {
        @Bindable var store = store
        let theme = settings.resolvedTheme
        let metrics = theme.metrics

        VStack(spacing: 0) {
            header
            Divider().overlay(theme.colors.divider)
            list
        }
        .frame(width: metrics.popoverWidth)
        .frame(maxHeight: metrics.popoverMaxHeight)
        .background(ThemedSurface())
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(metrics.panelCornerRadius), style: theme.cornerStyle))
        // Rendered here — an ancestor of `list`'s scroll view — rather than
        // inside each row's avatar stack: a pinned section header gets an
        // elevated compositing layer that no `.zIndex` inside a scrolled row
        // can out-rank, so the tooltip has to sit outside that hierarchy
        // entirely to draw above it. Resolving `AvatarTooltipAnchorKey`'s
        // anchor via this overlay's own `GeometryProxy` (rather than manually
        // diffing `.global` frames) lets SwiftUI do the coordinate-space
        // conversion, so the tooltip lands correctly centered regardless of
        // how deeply the hovered avatar is nested.
        .overlayPreferenceValue(AvatarTooltipAnchorKey.self) { anchor in
            GeometryReader { proxy in
                if let anchor, let avatarTooltip {
                    let avatarFrame = proxy[anchor]
                    AvatarTooltip(name: avatarTooltip.name)
                        .background(
                            GeometryReader { tooltipProxy in
                                Color.clear.preference(key: AvatarTooltipSizePreferenceKey.self, value: tooltipProxy.size)
                            }
                        )
                        .position(
                            x: avatarFrame.midX,
                            y: avatarFrame.minY - avatarTooltipSize.height / 2 - 8
                        )
                        .transaction { $0.animation = nil }
                        .opacity(avatarTooltip.isVisible ? 1 : 0)
                        .animation(.easeOut(duration: 0.12), value: avatarTooltip.isVisible)
                        .allowsHitTesting(false)
                }
            }
        }
        .onPreferenceChange(AvatarTooltipPreferenceKey.self) { avatarTooltip = $0 }
        .onPreferenceChange(AvatarTooltipSizePreferenceKey.self) { avatarTooltipSize = $0 }
        .studioTheme(theme)
        .preferredColorScheme(settings.appearancePreference.colorScheme)
        .transaction { $0.disablesAnimations = true }
        .animation(nil, value: settings.appearancePreference)
        // Remount on appearance so adaptive Liquid Glass colors don't crossfade.
        .id("\(settings.themePreference.rawValue)-\(settings.appearancePreference.rawValue)")
        .onAppear {
            searchFocused = true
            store.hideArchivedProjects = settings.hideArchivedProjects
            store.reconcileSelection()
        }
        .onChange(of: store.searchFocusToken) { _, _ in
            searchFocused = true
        }
        .onChange(of: store.query) { _, newValue in
            store.noteQueryChanged()
            store.reconcileSelection()
            AppDelegate.shared?.documentSearch.queryDidChange(newValue)
        }
        .onChange(of: store.groupBy) { _, _ in
            store.noteGroupByChanged()
            store.reconcileSelection()
        }
        .onChange(of: settings.hideArchivedProjects) { _, hide in
            store.hideArchivedProjects = hide
            store.noteHideArchivedChanged()
            store.reconcileSelection()
        }
        .onChange(of: settings.appearancePreference) { _, preference in
            AppDelegate.shared?.applyAppearance(preference)
        }
        .onChange(of: settings.themePreference) { _, _ in
            AppDelegate.shared?.applyAppearance(settings.appearancePreference)
        }
        .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequested)) { _ in
            openWindow(id: "settings")
        }
    }

    private var header: some View {
        @Bindable var store = store
        let theme = settings.resolvedTheme
        return VStack(spacing: 9) {
            if auth.needsReconnect || auth.status == .signedOut {
                authBanner
            }
            HStack(spacing: 8) {
                SearchFieldChrome {
                    TextField(
                        "Search projects, orgs, IDs, datasets, documents…",
                        text: $store.query
                    )
                    .textFieldStyle(.plain)
                    .font(theme.typography.search)
                    .foregroundStyle(theme.colors.text)
                    .focused($searchFocused)
                    .background(SearchFieldTuning())
                }
                Button {
                    AppDelegate.shared?.openSettingsWindow()
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(theme.colors.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Settings")
            }

            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    if store.isRefreshing || store.isSearchingDocuments {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(theme.colors.faint)
                    }
                    Text(projectCountLabel)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(theme.colors.faint)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(
                    store.isRefreshing ? "Refreshing projects"
                        : store.isSearchingDocuments ? "Searching documents"
                        : projectCountLabel
                )

                HStack(spacing: 6) {
                    Text("Group by")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.colors.faint)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    GroupByControl(
                        selection: $store.groupBy,
                        options: [
                            (.organization, "Org"),
                            (.lastEdited, "Last edited"),
                        ],
                        legend: groupByCycleGlyphs
                    )
                }

                Spacer()

                HStack(spacing: 4) {
                    HStack(spacing: 3) {
                        KeycapLegend([.symbol("arrow.up")], compact: true)
                        KeycapLegend([.symbol("arrow.down")], compact: true)
                    }
                    Text("Navigate")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(theme.colors.faint)

                HStack(spacing: 4) {
                    KeycapLegend(openDocumentGlyphs, compact: true)
                    Text("Document")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(theme.colors.faint)

                HStack(spacing: 4) {
                    KeycapLegend(openStudioGlyphs, compact: true)
                    Text("Studio")
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(theme.colors.faint)
            }
        }
        .padding(theme.metrics.headerPadding)
        .background(theme.surface.kind == .glass ? Color.clear : theme.colors.panelFill)
    }

    private var authBanner: some View {
        let theme = settings.resolvedTheme
        return HStack(spacing: 8) {
            Text(auth.needsReconnect ? "Session expired" : "Not connected to Sanity")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.colors.text)
            Spacer()
            Button(auth.needsReconnect ? "Reconnect" : "Connect") {
                AppDelegate.shared?.openSettingsWindow(pane: .account)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(theme.colors.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(theme.colors.primaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(5), style: theme.cornerStyle))
            .accessibilityLabel(auth.needsReconnect ? "Reconnect" : "Connect Sanity")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.colors.chipBackground)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(8), style: theme.cornerStyle))
    }

    private var list: some View {
        let theme = settings.resolvedTheme
        let groups = store.groups
        let favoriteIndexByID = store.favoriteIndexByID
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        Section {
                            ForEach(group.items) { item in
                                switch item {
                                case let .project(row):
                                    ProjectRowView(
                                        row: row,
                                        isSelected: store.selectedID == item.id,
                                        favoriteIndex: favoriteIndexByID[row.id]
                                    )
                                    // Favorite toggling moves the row across Section boundaries (into/out of the "Favorites" group), which LazyVStack can repaint stale on macOS unless the identity itself changes.
                                    .id("\(item.id)-\(row.curation.isFavorite)")
                                case let .document(project, document):
                                    DocumentRowView(
                                        row: project,
                                        document: document,
                                        listItemID: item.id,
                                        isSelected: store.selectedID == item.id
                                    )
                                    .id(item.id)
                                }
                            }
                            // Gap before the next group's label. It lives in the
                            // scrolling content rather than on the header: padding
                            // there leaves a transparent strip with rows sliding
                            // through it while pinned, and an offset to close that
                            // strip stops the header pinning at all.
                            if index < groups.count - 1 {
                                Color.clear.frame(height: 4)
                            }
                        } header: {
                            let isGlassPinned = theme.surface.kind == .glass && pinnedGroup(in: groups)?.id == group.id
                            organizationSectionHeader(for: group)
                                .opacity(isGlassPinned ? 0 : 1)
                                .allowsHitTesting(!isGlassPinned)
                                .accessibilityHidden(isGlassPinned)
                                .background {
                                    GeometryReader { proxy in
                                        Color.clear.preference(
                                            key: SectionHeaderMinYKey.self,
                                            value: [group.id: proxy.frame(in: .named("projectList")).minY]
                                        )
                                    }
                                }
                        }
                    }

                    if groups.isEmpty {
                        Text(emptyListMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.faint)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, theme.metrics.listPadding.leading)
                            .padding(.vertical, 26)
                    }
                }
                .padding(.bottom, theme.metrics.listPadding.bottom)
            }
            .scrollIndicators(settings.hideScrollbar ? .hidden : .automatic)
            .coordinateSpace(name: "projectList")
            .overlay(alignment: .top) {
                if theme.surface.kind == .glass {
                    GlassSurface(cornerRadius: 0, blendingMode: .withinWindow, preferSimpleMaterial: true)
                        .frame(height: 28)
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .black, location: 0),
                                    .init(color: .black, location: 0.45),
                                    .init(color: .clear, location: 1),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .allowsHitTesting(false)
                }
            }
            .overlay(alignment: .top) {
                if theme.surface.kind == .glass, let group = pinnedGroup(in: groups) {
                    organizationSectionHeader(for: group)
                }
            }
            .onPreferenceChange(SectionHeaderMinYKey.self) { headerMinYs = $0 }
            .frame(maxHeight: theme.metrics.listMaxHeight)
            .onChange(of: store.selectedID) { _, id in
                guard let id else { return }
                if reduceMotion {
                    proxy.scrollTo(id, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
    }

    private func pinnedGroup(in groups: [ProjectGroup]) -> ProjectGroup? {
        groups.last { (headerMinYs[$0.id] ?? .greatestFiniteMagnitude) <= 1 }
    }

    private func organizationSectionHeader(for group: ProjectGroup) -> SectionHeader {
        SectionHeader(
            title: group.title,
            itemCount: group.items.count,
            accessory: group.organizationId,
            accessoryCopied: store.copiedOrganizationID == group.organizationId,
            onAccessory: group.organizationId.map { id in
                { store.copyOrganizationID(id) }
            },
            isFavorite: group.organizationId.map(store.isOrganizationFavorite),
            onToggleFavorite: group.organizationId.map { id in
                { store.toggleOrganizationFavorite(id) }
            }
        )
    }

    private var projectCountLabel: String {
        if store.isRefreshing, store.totalCount == 0 {
            return "Refreshing…"
        }
        return "\(store.visibleRows.count) projects"
    }

    private var emptyListMessage: String {
        if !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if store.isSearchingDocuments {
                return "Searching documents…"
            }
            return "No projects match “\(store.query)”"
        }
        if store.isRefreshing, auth.isSignedIn {
            return "Fetching your projects… This can take a couple of minutes for larger accounts."
        }
        if auth.isSignedIn {
            return "No projects yet"
        }
        return "Connect Sanity to load projects"
    }

    /// Reflects the user's current "Open Studio" binding (default Return, or whatever
    /// they recorded in Settings → Keybindings) so this legend never drifts from reality.
    private var openStudioGlyphs: [KeyGlyph] {
        let modifierGlyphs = KeyGlyphMapping.modifierGlyphs(settings.openStudioModifierFlags)
        let keyGlyph = KeyGlyphMapping.glyph(forKeyCode: UInt16(settings.openStudioKeyCode), characters: settings.openStudioCharacters)
        return modifierGlyphs + [keyGlyph]
    }

    /// Reflects the user's current "Open Document" binding (default ⌘Return,
    /// or whatever they recorded in Settings → Keybindings) so this legend
    /// never drifts from reality.
    private var openDocumentGlyphs: [KeyGlyph] {
        let modifierGlyphs = KeyGlyphMapping.modifierGlyphs(settings.openDocumentModifierFlags)
        let keyGlyph = KeyGlyphMapping.glyph(forKeyCode: UInt16(settings.openDocumentKeyCode), characters: settings.openDocumentCharacters)
        return modifierGlyphs + [keyGlyph]
    }

    /// Reflects the user's current "Cycle group by" binding (default ⌘/, or whatever
    /// they recorded in Settings → Keybindings) so this legend never drifts from reality.
    private var groupByCycleGlyphs: [KeyGlyph] {
        let modifierGlyphs = KeyGlyphMapping.modifierGlyphs(settings.groupByCycleModifierFlags)
        let keyGlyph = KeyGlyphMapping.glyph(forKeyCode: UInt16(settings.groupByCycleKeyCode), characters: settings.groupByCycleCharacters)
        return modifierGlyphs + [keyGlyph]
    }

}

private struct SectionHeaderMinYKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct AvatarTooltipSizePreferenceKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        value = nextValue()
    }
}
