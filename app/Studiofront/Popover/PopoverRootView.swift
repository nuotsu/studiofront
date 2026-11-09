import SwiftUI
import ThemeKit
import StudioStore

struct PopoverRootView: View {
    @Environment(StudioStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(\.openWindow) private var openWindow
    @State private var avatarTooltip: AvatarTooltipDisplay?
    @State private var avatarTooltipSize: CGSize = .zero
    /// Sidebar highlight and jump requests. Held as an observable object (not
    /// plain @State here) so scroll-driven highlight changes never redraw
    /// the root, and with it the list mid-scroll.
    @State private var sidebar = SidebarState()

    // Header, sidebar, and list are separate views so each only re-renders
    // for the state it reads: arrow keys, copy feedback, and the pinned glass
    // header leave the search field alone, and the refresh spinner (in the
    // sidebar footer) leaves the list alone.
    var body: some View {
        let theme = settings.resolvedTheme
        let metrics = theme.metrics

        HStack(spacing: 0) {
            OrganizationSidebar(state: sidebar)
            Divider().overlay(theme.colors.divider)
            VStack(spacing: 0) {
                PopoverHeader()
                Divider().overlay(theme.colors.divider)
                ProjectList(sidebar: sidebar)
                    // A new scope needs fresh lazy-list geometry and scroll position.
                    .id(store.isolation)
                    .layoutPriority(1)
                if let isolation = store.isolation {
                    IsolationFooter(isolation: isolation)
                }
            }
        }
        .frame(width: metrics.popoverWidth, height: metrics.popoverContentHeight)
        .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius(metrics.panelCornerRadius), style: theme.cornerStyle))
        // NSPopover clips the full-size background to its native outline,
        // including the beak; controls remain inside the content safe area.
        .background(ThemedSurface().ignoresSafeArea())
        // Rendered here — an ancestor of `ProjectList`'s scroll view — rather than
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
                    AvatarTooltip(name: avatarTooltip.name, maximumWidth: max(0, proxy.size.width - 16))
                        .background(
                            GeometryReader { tooltipProxy in
                                Color.clear.preference(key: AvatarTooltipSizePreferenceKey.self, value: tooltipProxy.size)
                            }
                        )
                        .position(
                            x: min(max(avatarFrame.midX, avatarTooltipSize.width / 2 + 8),
                                   proxy.size.width - avatarTooltipSize.width / 2 - 8),
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
            store.hideArchivedProjects = settings.hideArchivedProjects
            store.reconcileSelection()
        }
        .onChange(of: settings.hideArchivedProjects) { _, hide in
            store.hideArchivedProjects = hide
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
}

/// Sits outside the scroll view, spanning the main column's bottom edge.
private struct IsolationFooter: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.studioTheme) private var theme
    var isolation: ListIsolation

    private var title: String {
        switch isolation {
        case let .organization(id):
            store.organizations.first { $0.id == id }?.name
                ?? store.rows.first { $0.project.organizationId == id }?.project.organizationName ?? id
        case let .recency(bucket): bucket.title
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: store.isolatedRecencyBucket != nil ? "calendar" : "line.3.horizontal.decrease")
            Text("Showing only \(title)").lineLimit(1)
            Spacer(minLength: 0)
            Button("Show all") { store.isolation = nil }
                .buttonStyle(.plain)
                .foregroundStyle(theme.colors.primaryText)
                .help("Exit isolated view (Esc)")
        }
        .font(.system(size: 11))
        .foregroundStyle(theme.colors.sub)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity)
        .background(theme.colors.chipBackground)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.divider).frame(height: 1)
        }
    }
}

/// Search field and the Settings button.
private struct PopoverHeader: View {
    @Environment(StudioStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AuthSession.self) private var auth
    @FocusState private var searchFocused: Bool

    var body: some View {
        @Bindable var store = store
        let theme = settings.resolvedTheme
        VStack(spacing: 9) {
            if auth.needsReconnect || auth.status == .signedOut {
                authBanner
            }
            HStack(spacing: 8) {
                SearchFieldChrome {
                    // Explicit prompt color: the default placeholder came out
                    // white on the light gray field in light mode.
                    TextField(
                        "Search projects, orgs, IDs, datasets, documents…",
                        text: $store.queryInput,
                        prompt: Text("Search projects, orgs, IDs, datasets, documents…")
                            .foregroundStyle(theme.colors.faint)
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
                .help("Settings (⌘,)")
                .accessibilityLabel("Settings")
            }
        }
        .padding(theme.metrics.headerPadding)
        .background(theme.surface.kind == .glass ? Color.clear : theme.colors.panelFill)
        .onAppear {
            searchFocused = true
        }
        .onChange(of: store.searchFocusToken) { _, _ in
            searchFocused = true
        }
        .onChange(of: store.query) { _, newValue in
            AppDelegate.shared?.documentSearch.queryDidChange(newValue)
        }
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
}

/// Gives a list row a known height without measuring it.
///
/// `LazyVStack` sizes its content by asking rows how tall they are. A row's
/// natural height comes from nested stacks, text and flexible frames, and
/// working it out (repeatedly, as the list changes) was the largest layout
/// cost left after the rows themselves were slimmed down. Every row here has
/// a fixed height, so this answers immediately and lays the row out once,
/// when it is actually placed.
private struct FixedHeightRow: Layout {
    var height: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin,
            proposal: ProposedViewSize(width: bounds.width, height: bounds.height)
        )
    }

    func spacing(subviews: Subviews, cache: inout ()) -> ViewSpacing {
        .zero
    }
}

/// One slice of a section's rounded card: side borders on every row, with
/// the top or bottom edge and corners only on the first or last row.
private struct CardSegment: ViewModifier {
    @Environment(\.studioTheme) private var theme
    var isFirst: Bool
    var isLast: Bool

    static let inset: CGFloat = 3

    func body(content: Content) -> some View {
        let radius = theme.cornerRadius(10)
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: isFirst ? radius : 0,
            bottomLeadingRadius: isLast ? radius : 0,
            bottomTrailingRadius: isLast ? radius : 0,
            topTrailingRadius: isFirst ? radius : 0,
            style: theme.cornerStyle
        )
        content
            .padding(EdgeInsets(
                top: isFirst ? Self.inset : 0,
                leading: Self.inset,
                bottom: isLast ? Self.inset : 0,
                trailing: Self.inset
            ))
            .background(shape.fill(theme.colors.chipBackground.opacity(0.5)))
            .overlay {
                // Extend the stroked shape past open edges, then clip, so
                // middle rows only show their side borders.
                shape
                    .strokeBorder(theme.colors.divider, lineWidth: 1)
                    .padding(EdgeInsets(top: isFirst ? 0 : -2, leading: 0, bottom: isLast ? 0 : -2, trailing: 0))
                    .allowsHitTesting(false)
            }
            .clipped()
            .padding(.horizontal, 8)
    }
}

/// The "N hidden" dropdown at the bottom of an org section, listing the
/// projects hidden from it with a button to show each again.
private struct HiddenProjectsDropdown: View {
    @Environment(\.studioTheme) private var theme
    var rows: [ProjectRow]
    var isExpanded: Bool
    var hasRowsAbove: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if hasRowsAbove {
                Rectangle()
                    .fill(theme.colors.divider)
                    .frame(height: 1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
            }
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                    Text(rows.count == 1 ? "1 hidden project" : "\(rows.count) hidden projects")
                        .font(.system(size: 10.5))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(theme.colors.faint)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isExpanded ? "Collapse hidden projects" : "Show hidden projects")

            if isExpanded {
                ForEach(rows) { row in
                    HiddenProjectListRow(row: row)
                }
            }
        }
    }
}

private struct HiddenProjectListRow: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store
    var row: ProjectRow

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            FaviconSource(host: ProjectRowChrome.faviconHost(for: row)) { favicon in
                ProjectAvatar(name: row.displayTitle, brandHex: row.project.brandColorHex, favicon: favicon, size: 20)
            }
            .opacity(0.5)
            Text(row.displayTitle)
                .font(theme.typography.meta)
                .foregroundStyle(theme.colors.faint)
                .lineLimit(1)
            Spacer(minLength: 4)
            Button {
                store.setProjectHidden(row.id, hidden: false)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "eye")
                    Text("Show")
                }
                .font(.system(size: 10))
                .foregroundStyle(isHovered ? theme.colors.text : theme.colors.faint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(row.displayTitle)")
        }
        .padding(.leading, 28)
        .padding(.trailing, 14)
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Open Studio") {
                AppDelegate.shared?.openStudio(for: row)
            }
            if let site = row.curation.primaryFrontendURL {
                Button("Open Site") { AppDelegate.shared?.openURL(site) }
            }
            if let manage = row.project.manageURL {
                Button("Manage Project") {
                    AppDelegate.shared?.openURL(manage)
                }
            }
            Button("Copy Project ID") {
                store.copy(row.project.id, feedbackKey: StudioStore.projectIDCopyKey(listItemID: row.id))
            }
            Divider()
            Button("Show Project", systemImage: "eye") {
                store.setProjectHidden(row.id, hidden: false)
            }
        }
    }
}

/// The grouped, scrolling project and document list.
private struct ProjectList: View {
    @Environment(StudioStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Environment(AuthSession.self) private var auth
    /// Which section header is currently pinned under the glass fade — updated
    /// only when the pinned id changes, not on every scroll-frame minY write.
    @State private var pinnedGroupID: String?
    /// Sidebar highlight and jump requests.
    var sidebar: SidebarState
    /// Last group the scroll position pointed at. The highlight only follows
    /// scrolling when this changes, so a jump to a group near the bottom
    /// (which can't reach the top) keeps its highlight.
    @State private var scrolledGroupID: String?
    /// A sidebar jump selects the group's first row; this lets
    /// `SelectionScroller` skip its usual center-on-selection scroll for
    /// that one change. A plain reference, so setting it redraws nothing.
    @State private var jumpSelection = JumpSelection()
    /// Org sections whose "hidden" dropdown is open.
    @State private var expandedHiddenGroupIDs: Set<String> = []

    /// The active group is the one whose header is pinned at the top. A
    /// larger allowance made a short group (one or two rows) lose the
    /// highlight to the group right below it after a jump.
    private static let activeHeaderThreshold: CGFloat = 8

    private static func jumpAnchorID(_ groupID: String) -> String {
        "group-anchor:\(groupID)"
    }

    var body: some View {
        let theme = settings.resolvedTheme
        let groups = store.groups
        let favoriteIndexByID = store.favoriteIndexByID
        let showFavoriteShortcuts = store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Read once here, not per row: a row reading `store.groups` redraws
        // whenever any part of the list changes. Selection, copy feedback and
        // pin state are read by small views inside the rows and headers, so
        // this body only re-runs when the list's contents change.
        let pinnedGroupShown = groups.first?.id == StudioStore.favoritesGroupID
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: Self.pinnedViews) {
                    // Jump targets sit right above each group's header (here
                    // for the first group, after the previous group's gap for
                    // the rest), so a jump lands the header exactly at the top.
                    // 1pt tall rather than 0: a zero-height target never counts
                    // as visible, which kept the lazy stack re-scrolling.
                    if let first = groups.first {
                        Color.clear.frame(height: 1).id(Self.jumpAnchorID(first.id))
                    }
                    ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                        Section {
                            // Clears the top blur's fade so the first row isn't
                            // softened while the list is scrolled to the top.
                            if index == 0, theme.surface.kind == .glass {
                                Color.clear.frame(height: 12)
                            }
                            // Each section reads as one rounded card under its
                            // sticky header, but every row draws its own slice
                            // of it, so rows stay direct children of the lazy
                            // stack and only on-screen rows get built.
                            let segmentCount = group.items.count + (group.hiddenRows.isEmpty ? 0 : 1)
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { position, item in
                                cardRow(
                                    item,
                                    isFirst: position == 0,
                                    isLast: position == segmentCount - 1,
                                    favoriteIndex: favoriteIndex(for: item, pinnedGroupShown: pinnedGroupShown, showShortcuts: showFavoriteShortcuts, indexByID: favoriteIndexByID)
                                )
                            }
                            if !group.hiddenRows.isEmpty {
                                HiddenProjectsDropdown(
                                    rows: group.hiddenRows,
                                    isExpanded: expandedHiddenGroupIDs.contains(group.id),
                                    hasRowsAbove: !group.items.isEmpty
                                ) {
                                    if expandedHiddenGroupIDs.contains(group.id) {
                                        expandedHiddenGroupIDs.remove(group.id)
                                    } else {
                                        expandedHiddenGroupIDs.insert(group.id)
                                    }
                                }
                                .modifier(CardSegment(isFirst: group.items.isEmpty, isLast: true))
                            }
                            // Gap before the next group's label. It lives in the
                            // scrolling content rather than on the header: padding
                            // there leaves a transparent strip with rows sliding
                            // through it while pinned, and an offset to close that
                            // strip stops the header pinning at all.
                            if index < groups.count - 1 {
                                Color.clear.frame(height: 7)
                                Color.clear.frame(height: 1).id(Self.jumpAnchorID(groups[index + 1].id))
                            }
                        } header: {
                            sectionHeader(for: group, isGlassPinned: theme.surface.kind == .glass && pinnedGroupID == group.id)
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
            .scrollEdgeEffectHidden(theme.surface.kind == .glass, for: .top)
            .coordinateSpace(name: "projectList")
            .overlay(alignment: .top) {
                if theme.surface.kind == .glass {
                    ListTopBlur()
                }
            }
            .overlay(alignment: .top) {
                if theme.surface.kind == .glass,
                   let pinnedID = pinnedGroupID,
                   let group = groups.first(where: { $0.id == pinnedID })
                {
                    GroupSectionHeader(group: group)
                }
            }
            .background(SelectionScroller(proxy: proxy, jumpSelection: jumpSelection))
            .onPreferenceChange(SectionHeaderMinYKey.self) { minYs in
                let next = groups.last { (minYs[$0.id] ?? .greatestFiniteMagnitude) <= 1 }?.id
                if next != pinnedGroupID {
                    pinnedGroupID = next
                }
                let scrolled = groups.last { (minYs[$0.id] ?? .greatestFiniteMagnitude) <= Self.activeHeaderThreshold }?.id
                    ?? groups.first?.id
                if scrolled != scrolledGroupID {
                    scrolledGroupID = scrolled
                    if sidebar.activeGroupID != scrolled {
                        sidebar.activeGroupID = scrolled
                    }
                }
            }
            .frame(maxHeight: .infinity)
            .task(id: sidebar.jumpRequest) {
                // Also runs on mount when a sidebar click exits isolation.
                // Isolated lists start at the top, ignoring prior browse jumps.
                guard store.isolation == nil,
                      let request = sidebar.jumpRequest else { return }
                await Task.yield()
                guard !Task.isCancelled,
                      let group = store.groups.first(where: { $0.id == request.groupID }) else { return }
                if let target = request.itemID ?? group.items.first?.id, store.selectedID != target {
                    jumpSelection.itemID = target
                    store.select(target)
                }
                // Not animated: an animated scroll across a lazy stack keeps
                // retargeting as rows realize at their real heights. One
                // follow-up pass corrects any estimate error after layout.
                let anchor = Self.jumpAnchorID(group.id)
                proxy.scrollTo(anchor, anchor: .top)
                await Task.yield()
                guard !Task.isCancelled else { return }
                proxy.scrollTo(anchor, anchor: .top)
            }
        }
    }

    /// ⌘1–9 legends go on the Pinned copies; by date (no Pinned group)
    /// they go on the project rows themselves.
    private func favoriteIndex(
        for item: PopoverListItem,
        pinnedGroupShown: Bool,
        showShortcuts: Bool,
        indexByID: [String: Int]
    ) -> Int? {
        guard showShortcuts else { return nil }
        switch item {
        case let .pinned(row):
            return indexByID[row.id]
        case let .project(row):
            return pinnedGroupShown ? nil : indexByID[row.id]
        case .studio, .document:
            return nil
        }
    }

    private static var pinnedViews: PinnedScrollableViews {
        return [.sectionHeaders]
    }

    /// A section's sticky header, reporting its position so the pinned
    /// header and the sidebar highlight can follow the scroll.
    @ViewBuilder
    private func sectionHeader(for group: ProjectGroup, isGlassPinned: Bool) -> some View {
        trackedSectionHeader(for: group, isGlassPinned: isGlassPinned)
    }

    private func trackedSectionHeader(for group: ProjectGroup, isGlassPinned: Bool) -> some View {
        GroupSectionHeader(group: group)
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

    /// One row in its slice of the section card. Row heights are constants,
    /// so the lazy stack is told the height instead of measuring each row's
    /// contents to find it.
    private func cardRow(_ item: PopoverListItem, isFirst: Bool, isLast: Bool, favoriteIndex: Int?) -> some View {
        let rowHeight = item.document == nil ? ProjectRowView.height : DocumentRowView.height
        let height = rowHeight + (isFirst ? CardSegment.inset : 0) + (isLast ? CardSegment.inset : 0)
        return FixedHeightRow(height: height) {
            listRow(item, favoriteIndex: favoriteIndex)
                .modifier(CardSegment(isFirst: isFirst, isLast: isLast))
        }
    }

    @ViewBuilder
    private func listRow(_ item: PopoverListItem, favoriteIndex: Int?) -> some View {
        switch item {
        case let .project(row):
            ProjectRowView(row: row, favoriteIndex: favoriteIndex)
                .id(item.id)
        case let .pinned(row):
            ProjectRowView(row: row, listItemID: item.id, favoriteIndex: favoriteIndex, showsOrganizationID: true)
                .id(item.id)
        case let .studio(row):
            ProjectRowView(row: row, listItemID: item.id, favoriteIndex: nil, showsOrganizationID: true)
                .id(item.id)
        case let .document(project, document):
            DocumentRowView(row: project, document: document, listItemID: item.id)
                .id(item.id)
        }
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
}

/// A section's sticky header. It reads copy feedback and pin state itself,
/// so copying an id or pinning an org redraws the headers, not the list.
private struct GroupSectionHeader: View {
    @Environment(StudioStore.self) private var store
    var groupID: String
    var title: String
    var organizationID: String?
    var itemCount: Int

    init(group: ProjectGroup) {
        groupID = group.id
        title = group.title
        organizationID = group.organizationId
        itemCount = group.items.count
    }

    var body: some View {
        // Scoped to this header so the sidebar's copy of the same id doesn't
        // also flash "copied".
        let copyKey = "header-org:\(groupID)"
        SectionHeader(
            title: title,
            itemCount: itemCount,
            accessory: organizationID,
            accessoryCopied: store.isShowingCopied(copyKey),
            onAccessory: organizationID.map { id in
                { store.copy(id, feedbackKey: copyKey) }
            },
            isFavorite: organizationID.map(store.isOrganizationFavorite),
            onToggleFavorite: organizationID.map { id in
                { store.toggleOrganizationFavorite(id) }
            }
        )
        .contextMenu {
            if let organizationID {
                OrganizationContextMenu(organizationID: organizationID, copyFeedbackKey: copyKey)
            } else if let bucket = RecencyBucket(rawValue: groupID) {
                DateContextMenu(bucket: bucket)
            }
        }
    }
}

/// Set by a sidebar jump so the selection change it causes isn't also
/// scrolled to the center.
private final class JumpSelection {
    var itemID: String?
}

/// Keeps the keyboard selection on screen. A separate, invisible view so the
/// list's own body doesn't depend on the selection: an arrow key re-runs
/// this and the affected rows' backgrounds, nothing else.
private struct SelectionScroller: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var proxy: ScrollViewProxy
    var jumpSelection: JumpSelection

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: store.selectedID) { _, id in
                guard let id else { return }
                let cameFromJump = id == jumpSelection.itemID
                jumpSelection.itemID = nil
                if cameFromJump { return }
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

/// Progressive blur under the pinned section header in Liquid Glass.
private struct ListTopBlur: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            // The dark material's scrim reads darker than the popover glass.
            .overlay(colorScheme == .dark ? Color.white.opacity(0.06) : Color.clear)
            .frame(height: 36)
            .padding(.horizontal, 1)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .allowsHitTesting(false)
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
