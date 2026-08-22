import AppKit
import Foundation
import Observation

@MainActor
@Observable
public final class StudioStore {
    public var rows: [ProjectRow]
    public var organizations: [OrganizationRecord]
    public var query: String = ""
    public var groupBy: GroupBy = .organization
    public var selectedID: String?
    public var copiedKey: String?
    public var searchFocusToken: UInt = 0
    public var isRefreshing: Bool = false
    public var hideArchivedProjects: Bool = true
    /// Defaults to free caps until `LicenseService` resolves a concrete entitlement.
    public var entitlement: StudioStoreEntitlement = .free { didSet { invalidateListCache() } }
    public var onCurationChanged: (() -> Void)?
    public var onRefreshRequested: (() -> Void)?
    /// Fired after `replaceRows` — the only point at which the set of
    /// eligible project ids for presence can change while the popover stays
    /// open (no per-row visibility/hide toggle exists yet).
    public var onRowsReplaced: (() -> Void)?
    /// Live, per-project document search results for the current query —
    /// populated by `DocumentSearchCoordinator` as each project's search
    /// resolves. Cleared whenever the query changes or drops below the
    /// coordinator's minimum length. Keyed by project id.
    public var liveDocumentMatchesByProject: [String: [EditedDocument]] = [:]
    /// Project ids with a live document search still in flight for the
    /// current query — drives the header's loading indicator.
    public var searchingProjectIDs: Set<String> = []
    public var isSearchingDocuments: Bool { !searchingProjectIDs.isEmpty }

    private var copyResetTask: Task<Void, Never>?

    private struct ListState {
        var visibleRows: [ProjectRow]
        var groups: [ProjectGroup]
        var flatVisibleIDs: [String]
        var favoriteIndexByID: [String: Int]
        var lockedProjectIDs: Set<String>
        var lockedOrganizationIDs: Set<String>
    }

    private var listStateGeneration = 0
    private var cachedListStateGeneration: Int?
    private var cachedListState: ListState?

    private var normalizedQuerySource = ""
    private var normalizedQueryNeedle = ""

    public init(
        rows: [ProjectRow] = [],
        organizations: [OrganizationRecord] = []
    ) {
        self.rows = rows
        self.organizations = organizations
        self.selectedID = rows.first(where: { $0.curation.isFavorite })?.id ?? rows.first?.id
    }

    public var totalCount: Int { rows.filter { !$0.curation.isHidden && !isArchivedAndHidden($0) }.count }

    public var visibleRows: [ProjectRow] {
        listState().visibleRows
    }

    private func isArchivedAndHidden(_ row: ProjectRow) -> Bool {
        hideArchivedProjects && row.project.isArchived
    }

    public var curationSnapshot: [ProjectCuration] {
        rows.map(\.curation)
    }

    public var organizationSnapshot: [PersistedOrganization] {
        organizations.map { PersistedOrganization(id: $0.id, name: $0.name, isFavorite: $0.isFavorite) }
    }

    /// The single source of truth for favorites order — shared by `groups` (what renders)
    /// and `jumpToFavorite` (what Cmd+N selects), so the two can never diverge.
    public var sortedFavorites: [ProjectRow] {
        sortedFavorites(from: visibleRows)
    }

    private func sortedFavorites(from visible: [ProjectRow]) -> [ProjectRow] {
        sortedByRecency(visible.filter(\.curation.isFavorite))
    }

    /// 1-based Cmd+N legend index for every current favorite, keyed by row id.
    public var favoriteIndexByID: [String: Int] {
        listState().favoriteIndexByID
    }

    public var groups: [ProjectGroup] {
        listState().groups
    }

    public func isProjectLocked(_ id: String) -> Bool {
        listState().lockedProjectIDs.contains(id)
    }

    public func isOrganizationLocked(_ id: String) -> Bool {
        listState().lockedOrganizationIDs.contains(id)
    }

    public var flatVisibleIDs: [String] {
        listState().flatVisibleIDs
    }

    /// Projects eligible for presence connections and live document search fan-out.
    public func eligibleProjectIDs(respectingArchivedSetting: Bool = true) -> [String] {
        rows
            .filter { row in
                !row.curation.isHidden
                    && !row.isUnavailable
                    && !(respectingArchivedSetting && hideArchivedProjects && row.project.isArchived)
            }
            .map(\.id)
    }

    /// Eligible projects capped by recency — limits presence/socket fan-out on large accounts.
    public func eligibleProjectIDsForPresence(maxCount: Int = 40) -> [String] {
        let eligible = Set(eligibleProjectIDs())
        let sorted = rows
            .filter { eligible.contains($0.id) }
            .sorted { lhs, rhs in
                switch (lhs.activity.lastEditedDocument?.editedAt, rhs.activity.lastEditedDocument?.editedAt) {
                case let (l?, r?): return l > r
                case (.some, .none): return true
                case (.none, .some): return false
                case (.none, .none): return false
                }
            }
        return Array(sorted.prefix(maxCount).map(\.id))
    }

    /// Cached document title matches from recent activity — used to skip network search when sufficient.
    public func cachedDocumentMatches(for row: ProjectRow) -> [EditedDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return cachedTitleMatches(for: row, needle: normalizedSearchNeedle)
    }

    public func noteQueryChanged() {
        invalidateListCache()
    }

    public func noteGroupByChanged() {
        invalidateListCache()
    }

    public func noteHideArchivedChanged() {
        invalidateListCache()
    }

    public func clearDocumentSearchState() {
        liveDocumentMatchesByProject = [:]
        searchingProjectIDs = []
        invalidateListCache()
    }

    public func setSearchingProjectIDs(_ ids: Set<String>) {
        searchingProjectIDs = ids
        invalidateListCache()
    }

    /// Applies live search results in one observable update per batch.
    public func applyDocumentSearchBatch(
        updates: [String: [EditedDocument]],
        completedProjectIDs: Set<String>
    ) {
        guard !updates.isEmpty || !completedProjectIDs.isEmpty else { return }
        if !updates.isEmpty {
            liveDocumentMatchesByProject.merge(updates) { _, new in new }
        }
        if !completedProjectIDs.isEmpty {
            searchingProjectIDs.subtract(completedProjectIDs)
        }
        invalidateListCache()
    }

    private func listState() -> ListState {
        if cachedListStateGeneration == listStateGeneration, let cached = cachedListState {
            return cached
        }

        let visible = computeVisibleRows()
        let groups = computeGroups(from: visible)
        let flatVisibleIDs = groups.flatMap { $0.items.map(\.id) }
        var favoriteIndexByID: [String: Int] = [:]
        for (index, row) in sortedFavorites(from: visible).enumerated() where index < 9 {
            favoriteIndexByID[row.id] = index + 1
        }
        let locked = computeLockedSets(from: visible)

        let state = ListState(
            visibleRows: visible,
            groups: groups,
            flatVisibleIDs: flatVisibleIDs,
            favoriteIndexByID: favoriteIndexByID,
            lockedProjectIDs: locked.projects,
            lockedOrganizationIDs: locked.organizations
        )
        cachedListState = state
        cachedListStateGeneration = listStateGeneration
        return state
    }

    private func invalidateListCache() {
        listStateGeneration += 1
    }

    /// Which projects/orgs the free tier keeps unlocked: favorites first, then
    /// most-recently-active — the same order `sortedFavorites`/`computeGroups`
    /// already use — walked until either the project or organization cap is
    /// hit, whichever comes first. Everything else in `visible` is locked.
    private func computeLockedSets(from visible: [ProjectRow]) -> (projects: Set<String>, organizations: Set<String>) {
        guard !entitlement.isUnlimited else { return ([], []) }
        let noOrgKey = "\u{0}no-organization"
        let ordered = sortedFavorites(from: visible) + sortedByRecency(visible.filter { !$0.curation.isFavorite })

        var unlockedProjectIDs: Set<String> = []
        var unlockedOrgKeys: Set<String> = []
        for row in ordered {
            let orgKey = row.project.organizationId ?? noOrgKey
            let projectCapHit = unlockedProjectIDs.count >= entitlement.maxFavoriteProjects
            let orgCapHit = !unlockedOrgKeys.contains(orgKey) && unlockedOrgKeys.count >= entitlement.maxFavoriteOrganizations
            guard !projectCapHit, !orgCapHit else { continue }
            unlockedProjectIDs.insert(row.id)
            unlockedOrgKeys.insert(orgKey)
        }

        let lockedProjects = Set(visible.map(\.id)).subtracting(unlockedProjectIDs)
        let lockedOrgs = Set(visible.compactMap(\.project.organizationId)).subtracting(unlockedOrgKeys)
        return (lockedProjects, lockedOrgs)
    }

    private var normalizedSearchNeedle: String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedQuerySource == trimmed { return normalizedQueryNeedle }
        normalizedQuerySource = trimmed
        normalizedQueryNeedle = normalize(trimmed)
        return normalizedQueryNeedle
    }

    private func computeVisibleRows() -> [ProjectRow] {
        rows.filter { !$0.curation.isHidden && !isArchivedAndHidden($0) && matches($0) }
    }

    private func computeGroups(from visible: [ProjectRow]) -> [ProjectGroup] {
        var result: [ProjectGroup] = []
        let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        // While searching, skip the Favorites pin and fold favorited projects into
        // their normal org / recency groups so results aren't reordered by star.
        if !isSearching {
            let favorites = sortedFavorites(from: visible)
            if !favorites.isEmpty {
                result.append(ProjectGroup(id: "favorites", title: "Favorites", items: groupItems(from: favorites)))
            }
        }

        let rest = isSearching ? visible : visible.filter { !$0.curation.isFavorite }
        switch groupBy {
        case .organization:
            let pinned = organizations.filter(\.isFavorite)
            let unpinned = organizations.filter { !$0.isFavorite }
            let orgOrder = isSearching ? organizations : pinned + unpinned
            var seen = Set<String>()
            for org in orgOrder {
                seen.insert(org.id)
                let items = rest.filter { $0.project.organizationId == org.id }
                if !items.isEmpty {
                    result.append(ProjectGroup(id: org.id, title: org.name, organizationId: org.id, items: groupItems(from: sortedByRecency(items))))
                }
            }
            let leftoverOrgs = Dictionary(grouping: rest.filter { row in
                guard let id = row.project.organizationId else { return false }
                return !seen.contains(id)
            }, by: { $0.project.organizationId ?? "other" })
            for (id, items) in leftoverOrgs.sorted(by: { lhs, rhs in
                (lhs.value.first?.project.organizationName ?? lhs.key)
                    .localizedCaseInsensitiveCompare(rhs.value.first?.project.organizationName ?? rhs.key)
                    == .orderedAscending
            }) {
                let title = items.first?.project.organizationName ?? id
                result.append(ProjectGroup(id: id, title: title, organizationId: id, items: groupItems(from: sortedByRecency(items))))
            }
            let orphans = rest.filter { $0.project.organizationId == nil }
            if !orphans.isEmpty {
                result.append(ProjectGroup(id: "other", title: "Other", items: groupItems(from: sortedByRecency(orphans))))
            }
        case .lastEdited:
            for bucket in RecencyBucket.allCases {
                let items = rest.filter { row in
                    guard let edited = row.activity.lastEditedDocument?.editedAt else {
                        return bucket == .earlier
                    }
                    return RecencyBucket.bucket(for: edited) == bucket
                }
                if !items.isEmpty {
                    result.append(ProjectGroup(id: bucket.rawValue, title: bucket.title, items: groupItems(from: sortedByRecency(items))))
                }
            }
        }
        return result
    }

    /// Interleaves document search rows immediately after each project when a
    /// query is active; otherwise returns plain project rows.
    private func groupItems(from projects: [ProjectRow]) -> [PopoverListItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return projects.map { .project($0) }
        }
        var items: [PopoverListItem] = []
        items.reserveCapacity(projects.count)
        for project in projects {
            items.append(.project(project))
            for document in matchingDocuments(for: project) {
                items.append(.document(project: project, document: document))
            }
        }
        return items
    }

    /// Documents matching the active query for a project — live Sanity results
    /// when available, cached title matches while search is pending.
    func matchingDocuments(for row: ProjectRow) -> [EditedDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let matches: [EditedDocument]
        if searchingProjectIDs.contains(row.id) {
            matches = cachedTitleMatches(for: row, needle: normalizedSearchNeedle)
        } else if let live = liveDocumentMatchesByProject[row.id] {
            matches = live
        } else {
            matches = cachedTitleMatches(for: row, needle: normalizedSearchNeedle)
        }
        return matches.filter { !Self.excludedSearchTypeNames.contains($0.typeName) }
    }

    /// Plugin / infra types that can still sit in the local recent-docs cache
    /// from older syncs — keep them out of interleaved search rows.
    private static let excludedSearchTypeNames: Set<String> = [
        "vercel.deploymentTarget",
        "webhook_deploy",
    ]

    private func cachedTitleMatches(for row: ProjectRow, needle: String) -> [EditedDocument] {
        func titleMatches(_ title: String) -> Bool {
            let normalized = normalize(title)
            return normalized.contains(needle) || initials(of: normalized).contains(needle)
        }
        var seen = Set<String>()
        var result: [EditedDocument] = []
        for doc in row.activity.recentDocuments where titleMatches(doc.title) {
            let key = doc.listItemID
            if seen.insert(key).inserted {
                result.append(doc)
            }
        }
        if let lastEdited = row.activity.lastEditedDocument, titleMatches(lastEdited.title) {
            let key = lastEdited.listItemID
            if seen.insert(key).inserted {
                result.insert(lastEdited, at: 0)
            }
        }
        return result
    }

    /// Newest last-edited document first; projects with no activity data sink to the bottom.
    private func sortedByRecency(_ items: [ProjectRow]) -> [ProjectRow] {
        items.sorted { lhs, rhs in
            switch (lhs.activity.lastEditedDocument?.editedAt, rhs.activity.lastEditedDocument?.editedAt) {
            case let (l?, r?): return l > r
            case (.some, .none): return true
            case (.none, .some): return false
            case (.none, .none): return false
            }
        }
    }

    public var selectedListItem: PopoverListItem? {
        guard let selectedID else { return nil }
        for group in groups {
            if let item = group.items.first(where: { $0.id == selectedID }) {
                return item
            }
        }
        return nil
    }

    public var selectedRow: ProjectRow? {
        if let selectedListItem {
            return selectedListItem.projectRow
        }
        guard let selectedID else { return nil }
        return visibleRows.first { $0.id == selectedID } ?? rows.first { $0.id == selectedID }
    }

    public func replaceRows(_ rows: [ProjectRow], organizations: [OrganizationRecord]) {
        let previous = selectedID
        self.rows = rows
        self.organizations = organizations
        if let previous, rows.contains(where: { $0.id == previous }) {
            selectedID = previous
        } else {
            selectedID = rows.first(where: { $0.curation.isFavorite })?.id ?? rows.first?.id
        }
        invalidateListCache()
        reconcileSelection()
        onRowsReplaced?()
    }

    public func clearLiveRows() {
        replaceRows([], organizations: [])
    }

    /// Updates one row's live presence in place, distinct from `replaceRows`,
    /// so a presence push never disturbs selection/scroll reconciliation or list derivation.
    public func setActiveUsers(_ members: [Member], forProjectID id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[index].activity.activeUsers = members
    }

    public func prepareForOpen() {
        searchFocusToken &+= 1
        reconcileSelection()
    }

    public func reconcileSelection() {
        let ids = flatVisibleIDs
        if ids.isEmpty {
            selectedID = nil
            return
        }
        if let selectedID, ids.contains(selectedID) { return }
        self.selectedID = ids.first
    }

    public func selectNext() {
        let ids = flatVisibleIDs
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            self.selectedID = ids[min(index + 1, ids.count - 1)]
        } else {
            selectedID = ids.first
        }
    }

    public func selectPrevious() {
        let ids = flatVisibleIDs
        guard !ids.isEmpty else { return }
        if let selectedID, let index = ids.firstIndex(of: selectedID) {
            self.selectedID = ids[max(index - 1, 0)]
        } else {
            selectedID = ids.last
        }
    }

    public func select(_ id: String) {
        selectedID = id
    }

    public func toggleFavorite(_ id: String) {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        var row = rows[index]
        row.curation.isFavorite.toggle()
        rows[index] = row
        invalidateListCache()
        reconcileSelection()
        onCurationChanged?()
    }

    public func toggleFavoriteOnSelection() {
        guard let projectID = selectedListItem?.projectRow.id else { return }
        toggleFavorite(projectID)
    }

    public func cycleGroupBy() {
        let all = GroupBy.allCases
        guard let index = all.firstIndex(of: groupBy) else { return }
        groupBy = all[(index + 1) % all.count]
        invalidateListCache()
    }

    public func isOrganizationFavorite(_ id: String) -> Bool {
        organizations.first(where: { $0.id == id })?.isFavorite ?? false
    }

    public func toggleOrganizationFavorite(_ id: String) {
        if let index = organizations.firstIndex(where: { $0.id == id }) {
            var org = organizations[index]
            org.isFavorite.toggle()
            organizations[index] = org
            invalidateListCache()
            onCurationChanged?()
            return
        }
        let name = rows.first(where: { $0.project.organizationId == id })?.project.organizationName ?? id
        organizations.append(OrganizationRecord(id: id, name: name, isFavorite: true))
        invalidateListCache()
        onCurationChanged?()
    }

    public func jumpToFavorite(_ oneBasedIndex: Int) {
        let favorites = sortedFavorites
        guard favorites.indices.contains(oneBasedIndex - 1) else { return }
        selectedID = favorites[oneBasedIndex - 1].id
    }

    public func copySelectedProjectID() {
        guard let projectID = selectedListItem?.projectRow.id else { return }
        copy(projectID, key: "project:\(projectID)")
    }

    public func copyProjectID(_ id: String) {
        copy(id, key: "project:\(id)")
    }

    public func copyOrganizationID(_ id: String) {
        copy(id, key: "org:\(id)")
    }

    public var copiedProjectID: String? {
        guard let copiedKey, copiedKey.hasPrefix("project:") else { return nil }
        return String(copiedKey.dropFirst("project:".count))
    }

    public var copiedOrganizationID: String? {
        guard let copiedKey, copiedKey.hasPrefix("org:") else { return nil }
        return String(copiedKey.dropFirst("org:".count))
    }

    public func refresh() {
        onRefreshRequested?()
    }

    public func clearQueryOrSignalDismiss() -> Bool {
        if !query.isEmpty {
            query = ""
            clearDocumentSearchState()
            invalidateListCache()
            reconcileSelection()
            return false
        }
        return true
    }

    private func copy(_ value: String, key: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedKey = key
        copyResetTask?.cancel()
        copyResetTask = Task {
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            if copiedKey == key {
                copiedKey = nil
            }
        }
    }

    private func matches(_ row: ProjectRow) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if !matchingDocuments(for: row).isEmpty { return true }
        let needle = normalizedSearchNeedle
        let fields: [String] = [
            row.displayTitle,
            row.project.displayName,
            row.curation.nickname ?? "",
            row.project.organizationName ?? "",
            row.project.organizationId ?? "",
            row.project.id,
            row.project.datasets.map(\.name).joined(separator: " "),
            row.activity.lastEditedDocument?.title ?? "",
            row.activity.recentDocuments.map(\.title).joined(separator: " "),
            row.curation.frontendLinks.map(\.label).joined(separator: " "),
            row.curation.extraStudioLinks.map(\.label).joined(separator: " "),
        ]
        return fields.contains { field in
            let normalized = normalize(field)
            return normalized.contains(needle) || initials(of: normalized).contains(needle)
        }
    }

    /// The document to show on a project row's activity caption line.
    public func documentDisplay(for row: ProjectRow) -> EditedDocument? {
        row.activity.lastEditedDocument
    }

    private func normalize(_ string: String) -> String {
        string.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }

    /// First letter of each word, e.g. "elevate experiences" -> "ee", so a
    /// query like "ee" matches "Elevate Experiences" the way an acronym would.
    private func initials(of normalizedString: String) -> String {
        normalizedString
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .compactMap(\.first)
            .map(String.init)
            .joined()
    }
}
