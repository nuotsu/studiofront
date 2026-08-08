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
            Divider().overlay(theme.colors.divider)
            footer
        }
        .frame(width: metrics.popoverWidth)
        .frame(maxHeight: metrics.popoverMaxHeight)
        .background(ThemedSurface())
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(metrics.panelCornerRadius), style: theme.cornerStyle))
        .studioTheme(theme)
        .preferredColorScheme(settings.appearancePreference.colorScheme)
        .id(settings.themePreference)
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

            HStack {
                HStack(spacing: 6) {
                    Text("Group by")
                        .font(.system(size: 9.5))
                        .textCase(.uppercase)
                        .tracking(0.6)
                        .foregroundStyle(theme.colors.faint)
                    GroupByControl(
                        selection: $store.groupBy,
                        options: [
                            (.organization, "Org"),
                            (.lastEdited, "Last edited"),
                        ]
                    )
                }
                Spacer()
                HStack(spacing: 5) {
                    if store.isRefreshing {
                        ProgressView()
                            .controlSize(.mini)
                            .tint(theme.colors.faint)
                    }
                    Text(projectCountLabel)
                }
                .font(.system(size: 9.5))
                .foregroundStyle(theme.colors.faint)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(store.isRefreshing ? "Refreshing projects" : projectCountLabel)
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
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(store.groups) { group in
                        Section {
                            ForEach(group.items) { row in
                                ProjectRowView(row: row, isSelected: store.selectedID == row.id)
                                    .id(row.id)
                            }
                        } header: {
                            SectionHeader(
                                title: group.title,
                                itemCount: group.organizationId != nil ? group.items.count : nil,
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

                    if store.visibleRows.isEmpty {
                        Text(emptyListMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(theme.colors.faint)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, theme.metrics.listPadding.leading)
                            .padding(.vertical, 26)
                    }
                }
                .padding(.top, theme.metrics.listPadding.top)
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

    private var footer: some View {
        let theme = settings.resolvedTheme
        return HStack {
            Text("↑↓ navigate · ↵ open Studio · ⌥↵ open site")
                .font(theme.typography.footer)
                .foregroundStyle(theme.colors.faint)
            Spacer()
            Button("Settings…") {
                AppDelegate.shared?.openSettingsWindow()
            }
            .buttonStyle(.plain)
            .font(theme.typography.footer)
            .foregroundStyle(theme.colors.sub)
            .accessibilityLabel("Settings")
        }
        .padding(theme.metrics.footerPadding)
    }
}
