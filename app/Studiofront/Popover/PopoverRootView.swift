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
        .onChange(of: store.query) { _, _ in
            store.reconcileSelection()
        }
        .onChange(of: store.groupBy) { _, _ in
            store.reconcileSelection()
        }
        .onChange(of: settings.hideArchivedProjects) { _, hide in
            store.hideArchivedProjects = hide
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
                    if store.isRefreshing {
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
                .accessibilityLabel(store.isRefreshing ? "Refreshing projects" : projectCountLabel)

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
                    KeycapLegend(openStudioGlyphs, compact: true)
                    Text("Open Studio")
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
        return ScrollViewReader { proxy in
            ScrollView {
                let groups = store.groups
                let favoriteIndexByID = store.favoriteIndexByID
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        Section {
                            ForEach(group.items) { row in
                                ProjectRowView(
                                    row: row,
                                    isSelected: store.selectedID == row.id,
                                    favoriteIndex: favoriteIndexByID[row.id]
                                )
                                    // Favorite toggling moves the row across Section boundaries (into/out of the "Favorites" group), which LazyVStack can repaint stale on macOS unless the identity itself changes.
                                    .id("\(row.id)-\(row.curation.isFavorite)")
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
                    }

                    if groups.isEmpty {
                        Text(emptyListMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, theme.metrics.listPadding.leading)
                            .padding(.vertical, 26)
                    }
                }
                .padding(.bottom, theme.metrics.listPadding.bottom)
            }
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

    private var projectCountLabel: String {
        if store.isRefreshing, store.totalCount == 0 {
            return "Refreshing…"
        }
        return "\(store.visibleRows.count) projects"
    }

    private var emptyListMessage: String {
        if !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "No projects match “\(store.query)”"
        }
        if store.isRefreshing, auth.isSignedIn {
            return "Loading projects…"
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

    /// Reflects the user's current "Cycle group by" binding (default ⌘/, or whatever
    /// they recorded in Settings → Keybindings) so this legend never drifts from reality.
    private var groupByCycleGlyphs: [KeyGlyph] {
        let modifierGlyphs = KeyGlyphMapping.modifierGlyphs(settings.groupByCycleModifierFlags)
        let keyGlyph = KeyGlyphMapping.glyph(forKeyCode: UInt16(settings.groupByCycleKeyCode), characters: settings.groupByCycleCharacters)
        return modifierGlyphs + [keyGlyph]
    }

}
