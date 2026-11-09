import SwiftUI
import ThemeKit
import StudioStore

/// Asks the project list to scroll a group to the top. The nonce lets the
/// same group be requested twice in a row.
struct GroupJumpRequest: Hashable {
    var groupID: String
    /// Row to select after the jump; the group's first row when nil.
    var itemID: String?
    var nonce: Int
}

/// One sidebar entry: a list group, or (in the Organizations view) an
/// organization that has no section of its own because all of its projects
/// are pinned, archived, or hidden.
struct SidebarEntry: Identifiable, Equatable {
    var id: String
    var title: String
    var organizationId: String?
    var projectCount: Int
    /// Where a click jumps; nil when the entry has nothing in the list.
    var jumpGroupID: String?
    var jumpItemID: String?

    init(group: ProjectGroup) {
        id = group.id
        title = group.title
        organizationId = group.organizationId
        projectCount = group.items.reduce(0) { count, item in
            if case .document = item { return count }
            return count + 1
        }
        jumpGroupID = group.id
    }

    init(id: String, title: String, organizationId: String?, projectCount: Int, jumpGroupID: String?, jumpItemID: String? = nil) {
        self.id = id
        self.title = title
        self.organizationId = organizationId
        self.projectCount = projectCount
        self.jumpGroupID = jumpGroupID
        self.jumpItemID = jumpItemID
    }
}

/// Shared between the sidebar and the list without going through the popover
/// root, so a scroll-driven highlight change only redraws the sidebar.
@MainActor
@Observable
final class SidebarState {
    /// The group the sidebar highlights: whichever is scrolled into view, or
    /// the one the user just jumped to.
    var activeGroupID: String?
    var jumpRequest: GroupJumpRequest?

    func requestJump(to groupID: String, selecting itemID: String? = nil) {
        activeGroupID = groupID
        jumpRequest = GroupJumpRequest(groupID: groupID, itemID: itemID, nonce: (jumpRequest?.nonce ?? 0) &+ 1)
    }
}

/// The popover's left column: the Organizations / Date toggle, one entry per
/// list group (click to jump, highlighted while it's on screen), and what the
/// user has hidden.
struct OrganizationSidebar: View {
    @Environment(StudioStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var state: SidebarState

    @State private var showsHidden = false

    var body: some View {
        @Bindable var store = store
        let theme = settings.resolvedTheme
        let groups = store.sidebarGroups
        let entries = sidebarEntries(groups: groups)
        let showsHiddenSection = store.groupBy == .organization && !store.hiddenOrganizationIDs.isEmpty

        VStack(alignment: .leading, spacing: 0) {
            GroupBySegmentedControl(selection: $store.groupBy, cycleGlyphs: groupByCycleGlyphs)
                .padding(.horizontal, 8)
                .padding(.top, theme.metrics.headerPadding.top)
                .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(entries) { entry in
                        SidebarGroupRow(
                            entry: entry,
                            state: state,
                            fallbackActiveID: groups.first?.id
                        )
                    }

                    if showsHiddenSection {
                        hiddenSection
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)

            SidebarFooter()
        }
        .frame(width: theme.metrics.sidebarWidth)
        .frame(maxHeight: .infinity, alignment: .top)
        // Same surface as the list: the popover's own background shows
        // through, so the sidebar keeps the theme's colors in both modes.
        .background(theme.surface.kind == .glass ? Color.clear : theme.colors.panelFill)
        .onChange(of: store.revealedOrganizationID) { _, id in
            if let id, store.hiddenOrganizationIDs.contains(id) { showsHidden = true }
            if id == nil { state.activeGroupID = nil }
        }
    }

    /// Isolates a hidden org without changing the sidebar entries.
    private func reveal(_ organizationID: String) {
        if store.revealedOrganizationID == organizationID {
            store.revealedOrganizationID = nil
            return
        }
        store.revealedOrganizationID = organizationID
    }

    @ViewBuilder
    private var hiddenSection: some View {
        let theme = settings.resolvedTheme
        let hiddenOrgs = store.hiddenOrganizations
        VStack(alignment: .leading, spacing: 1) {
            Rectangle()
                .fill(theme.colors.divider)
                .frame(height: 1)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)

            Button {
                showsHidden.toggle()
                if !showsHidden, let id = store.revealedOrganizationID, store.hiddenOrganizationIDs.contains(id) {
                    store.revealedOrganizationID = nil
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10))
                        .frame(width: 16)
                    Text(hiddenOrgs.count == 1 ? "1 hidden org" : "\(hiddenOrgs.count) hidden orgs")
                        .font(.system(size: 11))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                        .rotationEffect(.degrees(showsHidden ? 90 : 0))
                }
                .foregroundStyle(theme.colors.faint)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(showsHidden ? "Collapse hidden organizations" : "Show hidden organizations")

            if showsHidden {
                ForEach(hiddenOrgs) { org in
                    HiddenOrganizationRow(
                        organization: org,
                        isRevealed: store.revealedOrganizationID == org.id,
                        onReveal: { reveal(org.id) }
                    )
                }
            }
        }
    }

    /// In the Organizations view (not searching), lists every organization
    /// you can access, not just those with a section: an org whose projects
    /// are all pinned, archived, or hidden still shows, and jumps to its
    /// first pinned project when it has one. Counts come from the browse
    /// list, so they hold steady while a hidden org is revealed. Otherwise
    /// the entries mirror the list groups.
    private func sidebarEntries(groups: [ProjectGroup]) -> [SidebarEntry] {
        let isSearching = !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard store.groupBy == .organization, !isSearching || store.isolation != nil else {
            return groups.map(SidebarEntry.init(group:))
        }

        let browseRows = store.browseRows
        let pinnedRows = browseRows.filter(\.curation.isFavorite)
        var entries: [SidebarEntry] = []
        if !pinnedRows.isEmpty {
            entries.append(SidebarEntry(
                id: StudioStore.favoritesGroupID,
                title: "Pinned",
                organizationId: nil,
                projectCount: pinnedRows.count,
                jumpGroupID: StudioStore.favoritesGroupID
            ))
        }
        var projectCountByOrg: [String: Int] = [:]
        for row in browseRows {
            guard let orgID = row.project.organizationId else { continue }
            projectCountByOrg[orgID, default: 0] += 1
        }
        let groupIDs = Set(groups.map(\.id))

        var listed = Set<String>()
        for org in store.orderedOrganizations where !store.hiddenOrganizationIDs.contains(org.id) {
            listed.insert(org.id)
            let count = projectCountByOrg[org.id] ?? 0
            let hasSection = groupIDs.contains(org.id)
            entries.append(SidebarEntry(
                id: org.id, title: org.name, organizationId: org.id,
                projectCount: count, jumpGroupID: hasSection ? org.id : nil
            ))
        }
        // Orgs missing from the org directory, and "Other".
        for group in groups where group.id != StudioStore.favoritesGroupID && !listed.contains(group.id) {
            entries.append(SidebarEntry(group: group))
        }
        let pinnedIDs = store.pinnedOrganizationIDs
        return entries.enumerated().sorted { lhs, rhs in
            let lPinned = lhs.element.id == StudioStore.favoritesGroupID || lhs.element.organizationId.map(pinnedIDs.contains) == true
            let rPinned = rhs.element.id == StudioStore.favoritesGroupID || rhs.element.organizationId.map(pinnedIDs.contains) == true
            if lPinned != rPinned { return lPinned }
            if lPinned { return lhs.offset < rhs.offset }
            let order = lhs.element.title.localizedStandardCompare(rhs.element.title)
            return order == .orderedSame ? lhs.element.id < rhs.element.id : order == .orderedAscending
        }.map(\.element)
    }

    /// Reflects the user's current "Cycle group by" binding (default ⌘/).
    private var groupByCycleGlyphs: [KeyGlyph] {
        let modifierGlyphs = KeyGlyphMapping.modifierGlyphs(settings.groupByCycleModifierFlags)
        let keyGlyph = KeyGlyphMapping.glyph(forKeyCode: UInt16(settings.groupByCycleKeyCode), characters: settings.groupByCycleCharacters)
        return modifierGlyphs + [keyGlyph]
    }
}

/// Project count and the refresh / search spinner. Its own view so the
/// spinner turning on and off (several times per search) redraws only this
/// line and not the whole sidebar.
private struct SidebarFooter: View {
    @Environment(StudioStore.self) private var store
    @Environment(\.studioTheme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            if store.isRefreshing || store.isSearchingDocuments {
                ProgressView()
                    .controlSize(.mini)
                    .tint(theme.colors.faint)
            }
            Text(countLabel)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .font(.system(size: 9.5))
        .foregroundStyle(theme.colors.faint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle().fill(theme.colors.divider).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            store.isRefreshing ? "Refreshing projects"
                : store.isSearchingDocuments ? "Searching documents"
                : countLabel
        )
    }

    private var countLabel: String {
        if store.isRefreshing, store.totalCount == 0 {
            return "Refreshing…"
        }
        let isSearching = !store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isSearching {
            let count = store.flatVisibleIDs.count
            return count == 1 ? "1 result" : "\(count) results"
        }
        // Reading the groups keeps this label current when projects or orgs
        // are hidden; `browseRows` alone is served from a cache.
        _ = store.sidebarGroups.count
        let rows = store.browseRows
        // Every org the Organizations view lists (all orgs you can access,
        // minus hidden ones).
        let orgCount = Set(store.organizations.map(\.id))
            .union(rows.compactMap(\.project.organizationId))
            .subtracting(store.hiddenOrganizationIDs)
            .count
        let projects = rows.count == 1 ? "1 project" : "\(rows.count) projects"
        let orgs = orgCount == 1 ? "1 org" : "\(orgCount) orgs"
        return "\(orgs) · \(projects)"
    }
}

/// Organizations / Date toggle at the top of the sidebar.
private struct GroupBySegmentedControl: View {
    @Environment(\.studioTheme) private var theme
    @Binding var selection: GroupBy
    var cycleGlyphs: [KeyGlyph]

    var body: some View {
        HStack(spacing: 2) {
            segment(.organization, title: "Organizations")
            segment(.lastEdited, title: "Date")
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius(7), style: theme.cornerStyle)
                .fill(theme.colors.chipBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius(7), style: theme.cornerStyle)
                .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
        )
        .help("Group by organization or last edited (\(Self.shortcutText(cycleGlyphs)))")
    }

    /// Plain-text form of a keycap legend for tooltips, e.g. "⌘/".
    private static func shortcutText(_ glyphs: [KeyGlyph]) -> String {
        glyphs.map { glyph in
            switch glyph {
            case let .text(text): text
            case let .symbol(name):
                switch name {
                case "command": "⌘"
                case "shift": "⇧"
                case "option": "⌥"
                case "control": "⌃"
                case "return": "↩"
                default: ""
                }
            }
        }
        .joined()
    }

    private func segment(_ value: GroupBy, title: String) -> some View {
        let isOn = selection == value
        return Button {
            selection = value
        } label: {
            Text(title)
                .font(.system(size: 10.5, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? theme.colors.text : theme.colors.sub)
                .frame(maxWidth: .infinity)
                .frame(height: 20)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius(5), style: theme.cornerStyle)
                        .fill(isOn ? theme.colors.selection : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(value == .organization ? "Group by organization" : "Group by last edited")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

enum SidebarMetrics {
    static let iconSize: CGFloat = 32

    static func organizationURL(_ id: String) -> URL? {
        URL(string: "https://www.sanity.io/organizations/\(id)")
    }
}

/// Works out whether an entry is highlighted or pinned and passes plain
/// values down. Scrolling the list changes the highlight often; this tiny
/// body re-runs for every entry, but `SidebarGroupRowContent` (the expensive
/// part, with the favicon preview) only re-runs for the entries that changed.
private struct SidebarGroupRow: View {
    @Environment(StudioStore.self) private var store

    var entry: SidebarEntry
    var state: SidebarState
    var fallbackActiveID: String?

    var body: some View {
        let isActive = store.revealedOrganizationID.map { $0 == entry.organizationId }
            ?? store.isolatedRecencyBucket.map { $0.rawValue == entry.id }
            ?? (entry.jumpGroupID == entry.id && entry.id == (state.activeGroupID ?? fallbackActiveID))
        let isPinned = entry.organizationId.map(store.isOrganizationFavorite) ?? false
        SidebarGroupRowContent(entry: entry, isActive: isActive, isPinned: isPinned, state: state)
            .equatable()
    }
}

private struct SidebarGroupRowContent: View, Equatable {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store

    var entry: SidebarEntry
    var isActive: Bool
    var isPinned: Bool
    var state: SidebarState

    @State private var isHovered = false

    nonisolated static func == (lhs: SidebarGroupRowContent, rhs: SidebarGroupRowContent) -> Bool {
        lhs.entry == rhs.entry && lhs.isActive == rhs.isActive && lhs.isPinned == rhs.isPinned && lhs.state === rhs.state
    }

    var body: some View {
        let organizationID = entry.organizationId
        // Orgs with nothing in the list (all projects archived or hidden).
        let isEmpty = entry.jumpGroupID == nil
        let showsActions = organizationID != nil && (isHovered || isPinned)
        // Width the overlaid buttons cover: Dashboard (hover only) + Pin.
        let actionsWidth: CGFloat = showsActions ? (isHovered ? 41 : 20) : 0
        HStack(spacing: 8) {
            SidebarGroupIcon(entry: entry)
                .opacity(isEmpty ? 0.5 : 1)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(theme.typography.projectName)
                    .foregroundStyle(isActive ? theme.colors.text : (isEmpty ? theme.colors.faint : theme.colors.sub))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                if let organizationID {
                    SidebarIDChip(id: organizationID)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            // Names run under the buttons and fade out instead of truncating,
            // so the buttons read as floating over the row.
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .mask(SidebarFadeMask(clearWidth: actionsWidth, fadeWidth: showsActions ? 24 : 14))
            .overlay(alignment: .trailing) {
                if let organizationID, showsActions {
                    HStack(spacing: 1) {
                        if isHovered {
                            SidebarIconButton(
                                image: Image("SanityDashboard"),
                                imageSize: 13,
                                label: "Open organization in Sanity"
                            ) {
                                if let url = SidebarMetrics.organizationURL(organizationID) {
                                    AppDelegate.shared?.openURL(url)
                                }
                            }
                        }
                        SidebarIconButton(
                            image: Image(systemName: isPinned ? "pin.fill" : "pin"),
                            imageSize: 10,
                            label: isPinned ? "Unpin organization" : "Pin organization to top",
                            activeColor: isPinned ? theme.colors.star : nil
                        ) {
                            store.toggleOrganizationFavorite(organizationID)
                        }
                    }
                }
            }
            Text("\(entry.projectCount)")
                .font(.system(size: 9.5))
                .monospacedDigit()
                .foregroundStyle(theme.colors.faint)
                .frame(minWidth: 14, alignment: .center)
                .padding(.leading, -7)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius(7), style: theme.cornerStyle)
                .fill(isActive ? theme.colors.selection : (isHovered ? theme.colors.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovered = $0 }
        .help(isEmpty ? "No projects listed: they're archived or hidden" : "")
        .contextMenu {
            if let organizationID {
                OrganizationContextMenu(organizationID: organizationID)
            } else if let bucket = RecencyBucket(rawValue: entry.id) {
                DateContextMenu(bucket: bucket)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(entry.title), \(entry.projectCount) projects")
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .accessibilityAction { select() }
    }

    private func select() {
        store.isolation = nil
        guard let groupID = entry.jumpGroupID else { return }
        state.requestJump(to: groupID, selecting: entry.jumpItemID)
    }
}

/// The org id under an org's name. Copies on click, with feedback on this
/// chip only, and a hit area slightly smaller than the text so a click near
/// it still selects the sidebar entry.
private struct SidebarIDChip: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store
    var id: String

    @State private var isHovered = false

    static func copyKey(_ id: String) -> String { "sidebar-org:\(id)" }

    var body: some View {
        let copied = store.isShowingCopied(Self.copyKey(id))
        Text(copied ? "copied ✓" : id)
            .font(theme.typography.chip)
            .foregroundStyle(copied ? theme.colors.copied : theme.colors.faint.opacity(isHovered ? 1 : 0.7))
            .lineLimit(1)
            .contentShape(Rectangle().inset(by: 2))
            .onTapGesture {
                store.copy(id, feedbackKey: Self.copyKey(id))
            }
            .onHover { isHovered = $0 }
            .help("Copy organization ID")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(copied ? "Copied" : "Copy organization ID \(id)")
    }
}

/// Bare icon button for sidebar rows: faint, full text color and a soft
/// backdrop on hover.
private struct SidebarIconButton: View {
    @Environment(\.studioTheme) private var theme
    var image: Image
    var imageSize: CGFloat = 11
    var label: String
    /// Color when "on" (e.g. a filled pin); hover still brightens it.
    var activeColor: Color?
    var action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            image
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: imageSize, height: imageSize)
                .foregroundStyle(activeColor ?? (isHovered ? theme.colors.text : theme.colors.faint))
                .frame(width: 20, height: 20)
                .background(
                    RoundedRectangle(cornerRadius: theme.cornerRadius(5), style: theme.cornerStyle)
                        .fill(isHovered ? theme.colors.hover : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// A hidden org: click to isolate its projects; click again or Esc to exit.
private struct HiddenOrganizationRow: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store

    var organization: OrganizationRecord
    var isRevealed: Bool
    var onReveal: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 8) {
            OrganizationPreview(organizationID: organization.id, name: organization.name)
                .opacity(isRevealed ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 1) {
                Text(organization.name)
                    .font(.system(size: 11, weight: isRevealed ? .medium : .regular))
                    .foregroundStyle(isRevealed ? theme.colors.text : theme.colors.faint)
                    .lineLimit(1)
                SidebarIDChip(id: organization.id)
            }
            Spacer(minLength: 2)
            SidebarIconButton(
                image: Image(systemName: "eye"),
                imageSize: 12,
                label: "Show this organization"
            ) {
                store.revealedOrganizationID = nil
                store.setOrganizationHidden(organization.id, hidden: false)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius(7), style: theme.cornerStyle)
                .fill(isRevealed ? theme.colors.selection : (isHovered ? theme.colors.hover : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onReveal()
        }
        .onHover { isHovered = $0 }
        .help(isRevealed ? "Hide its projects again (Esc)" : "Isolate this organization’s projects")
        .contextMenu {
            OrganizationContextMenu(organizationID: organization.id)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isRevealed ? .isSelected : [])
    }
}

/// Keep organization menus in the same order as project menus:
/// destinations and IDs, pin order, then visibility.
struct OrganizationContextMenu: View {
    @Environment(StudioStore.self) private var store
    var organizationID: String
    var copyFeedbackKey: String? = nil

    var body: some View {
        let isPinned = store.isOrganizationFavorite(organizationID)
        let isHidden = store.hiddenOrganizationIDs.contains(organizationID)
        Button("Manage Organization") {
            if let url = SidebarMetrics.organizationURL(organizationID) {
                AppDelegate.shared?.openURL(url)
            }
        }
        Button("Copy Organization ID") {
            store.copy(organizationID, feedbackKey: copyFeedbackKey ?? SidebarIDChip.copyKey(organizationID))
        }
        Divider()
        Button(isPinned ? "Unpin" : "Pin") {
            store.toggleOrganizationFavorite(organizationID)
        }
        if isPinned {
            Button {
                store.movePinnedOrganization(organizationID, by: -1)
            } label: {
                Label("Move Up", systemImage: "arrow.up").labelStyle(.titleAndIcon)
            }
            .disabled(!store.canMovePinnedOrganization(organizationID, by: -1))
            Button {
                store.movePinnedOrganization(organizationID, by: 1)
            } label: {
                Label("Move Down", systemImage: "arrow.down").labelStyle(.titleAndIcon)
            }
            .disabled(!store.canMovePinnedOrganization(organizationID, by: 1))
        }
        Divider()
        Toggle("Isolate", isOn: Binding(
            get: { store.revealedOrganizationID == organizationID },
            set: { store.revealedOrganizationID = $0 ? organizationID : nil }
        ))
        Button(isHidden ? "Show Organization" : "Hide Organization", systemImage: isHidden ? "eye" : "eye.slash") {
            if store.revealedOrganizationID == organizationID {
                store.revealedOrganizationID = nil
            }
            store.setOrganizationHidden(organizationID, hidden: !isHidden)
        }
    }
}

struct DateContextMenu: View {
    @Environment(StudioStore.self) private var store
    var bucket: RecencyBucket

    var body: some View {
        Toggle("Isolate", isOn: Binding(
            get: { store.isolatedRecencyBucket == bucket },
            set: { store.isolatedRecencyBucket = $0 ? bucket : nil }
        ))
    }
}

private struct SidebarGroupIcon: View {
    @Environment(\.studioTheme) private var theme
    var entry: SidebarEntry

    var body: some View {
        Group {
            if entry.id == StudioStore.favoritesGroupID {
                symbol("pin.fill", color: theme.colors.star)
            } else if entry.id == StudioStore.studiosGroupID {
                symbol("magnifyingglass", color: theme.colors.faint)
            } else if let organizationID = entry.organizationId {
                OrganizationPreview(organizationID: organizationID, name: entry.title)
            } else if RecencyBucket(rawValue: entry.id) != nil {
                symbol("calendar", color: theme.colors.faint)
            } else {
                symbol("tray", color: theme.colors.faint)
            }
        }
        .frame(width: SidebarMetrics.iconSize, height: SidebarMetrics.iconSize)
        .accessibilityHidden(true)
    }

    private func symbol(_ name: String, color: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 13))
            .foregroundStyle(color)
    }
}

/// An org's avatar: a 2×2 grid of favicons from up to four of its projects
/// (pinned first). One spare quadrant indicates hidden projects.
private struct OrganizationPreview: View {
    @Environment(\.studioTheme) private var theme
    @Environment(StudioStore.self) private var store
    var organizationID: String
    var name: String

    private static let gap: CGFloat = 2
    private static let inset: CGFloat = 2

    var body: some View {
        let size = SidebarMetrics.iconSize
        let cell = (size - Self.inset * 2 - Self.gap) / 2
        let previewRows = store.previewRows(forOrganization: organizationID)
        let rows = previewRows.filter { !$0.curation.isHidden }
        // Hidden candidates only fit when fewer than four visible projects
        // exist. Collapse them into one indicator, leaving other slots empty.
        let hiddenSlot = previewRows.contains { $0.curation.isHidden } ? rows.count : nil
        let slots: [ProjectRow?] = (0..<4).map { rows.indices.contains($0) ? rows[$0] : nil }
        VStack(spacing: Self.gap) {
            HStack(spacing: Self.gap) {
                slot(slots[0], showsHidden: hiddenSlot == 0, cell: cell)
                slot(slots[1], showsHidden: hiddenSlot == 1, cell: cell)
            }
            HStack(spacing: Self.gap) {
                slot(slots[2], showsHidden: hiddenSlot == 2, cell: cell)
                slot(slots[3], showsHidden: hiddenSlot == 3, cell: cell)
            }
        }
        .padding(Self.inset)
        .frame(width: size, height: size)
        .background(
            RoundedRectangle(cornerRadius: theme.cornerRadius(8), style: theme.cornerStyle)
                .fill(theme.colors.tagBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: theme.cornerRadius(8), style: theme.cornerStyle)
                .strokeBorder(theme.colors.chipBorder, lineWidth: 1)
        )
        .help(name)
    }

    @ViewBuilder
    private func slot(_ row: ProjectRow?, showsHidden: Bool, cell: CGFloat) -> some View {
        if let row {
            PreviewFavicon(row: row, size: cell)
        } else if showsHidden {
            Image(systemName: "eye.slash")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(theme.colors.faint)
                .frame(width: cell, height: cell)
                .help("Hidden projects")
                .accessibilityLabel("Hidden projects")
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }
}

private struct PreviewFavicon: View {
    var row: ProjectRow
    var size: CGFloat

    var body: some View {
        FaviconSource(host: ProjectRowChrome.faviconHost(for: row)) { favicon in
            ProjectAvatar(name: row.displayTitle, brandHex: row.project.brandColorHex, favicon: favicon, size: size)
        }
    }
}

/// Opaque, then a gradient fade, then fully clear at the trailing edge
/// (where overlaid buttons sit).
private struct SidebarFadeMask: View {
    var clearWidth: CGFloat
    var fadeWidth: CGFloat

    var body: some View {
        HStack(spacing: 0) {
            Rectangle().fill(.black)
            LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: fadeWidth)
            Color.clear.frame(width: clearWidth)
        }
    }
}
